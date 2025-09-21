# lib/Contract/Declare2.pm
package Contract::Declare2;

use Types::Standard ();
BEGIN { eval { require Type::Tiny::XS; 1 } } # просто активирует ускорения


use strict;
use warnings;
use Keyword::Simple;
use Text::Balanced qw(extract_bracketed);
use Attribute::Handlers;
use Class::MOP ();

use Scalar::Util qw(blessed);
use Sub::Util    qw(set_subname);

use Data::Dumper;

my %SEEN;
our %IFACE;  # $IFACE{$iface_pkg}{$method} = { in_checks=>[CODE..], out_check=>CODE|undef }

INIT {
    while (my ($k, $v) = each(%SEEN)) {
        __PACKAGE__->interface($k, $v);
    }
}


sub import {
    Keyword::Simple::define 'interface' => sub {
        my $ref = shift;          # ссылка на остаток исходника после слова 'interface'
        # 1) имя интерфейса (допускаем ::)
        $$ref =~ /\A\s*([A-Za-z_]\w*(?:::\w+)*)\s*/
            or die "interface: expected name";
        my $name = $1;
        my $after_name = $+[0];

        # 2) сбалансированный блок { ... }
        my ($block, $rest) = extract_bracketed(substr($$ref, $after_name), '{}');
        $block or die "interface $name: expected {...} block";

        # 3) длина потребленного префикса = имя + блок
        my $consumed = $after_name + length($block);

        # 4) схаваем опциональную точку с запятой после блока
        my $tail = substr($$ref, $consumed);
        $tail =~ s/\A\s*;?//;

        # 5) подмена только конструкции interface → package … { … };
        $$ref = "package $name $block;" . $tail;
    };
}

sub UNIVERSAL::Args :ATTR(CODE) {
    my ($pkg, $sym, $coderef, $attr, $data, $phase, $file, $line) = @_;
    my $name = *{$sym}{NAME};
    $SEEN{$pkg}{$name}{args} = $data;
}

sub UNIVERSAL::Returns :ATTR(CODE) {
    my ($pkg, $sym, $coderef, $attr, $data, $phase, $file, $line) = @_;
    my $name = *{$sym}{NAME};
    $SEEN{$pkg}{$name}{returns} = $data;
}

sub unimport {
    Keyword::Simple::undefine 'interface';
}


sub interface {
    my ($class, $iface, $contract) = @_;
    die "interface: need package name"      unless defined $iface && length $iface;
    die "interface: need hashref spec"      unless ref($contract) eq 'HASH';

    my $meta  = Class::MOP::Class->initialize($iface);
    my $store = ($IFACE{$iface} //= {});



    use Data::Dumper;

    for my $method (sort keys %$contract) {
        my $spec = $contract->{$method} || {};
        my $args = $spec->{args}    || [];
        my $ret  = exists $spec->{returns} ? $spec->{returns} : undef;

        # 1) заранее компилируем предикаты (XS если доступен)
        my @in_checks  = map { _compile_check($_) } @$args;
        my @out_checks = map { _compile_check($_) } @$ret;
        #my $out_check = defined $ret ? _compile_check($ret) : undef;

        $store->{$method} = {
            in_checks => \@in_checks,
            out_check => \@out_checks,
        };

        # 2) ставим метод-обёртку в интерфейс
        _install_wrapper($meta, $iface, $method, $store->{$method});
    }

    # 3) конструктор new($impl)
    _install_constructor($meta, $iface);

    return $iface;
}

# ---- utils: компиляция типов в быстрые предикаты ----
sub _compile_check {
    my ($t) = @_;

    # Type::Tiny объект?
    if (eval { $t->isa('Type::Tiny') }) {
        # compiled_check — использует XS-бэкенд, если он установлен
        my $pred = $t->compiled_check;
        return sub { $pred->($_[0]) ? 1 : 0 };
    }

    # Строка типа — попытаемся достать Type::Tiny из Types::Standard
    if (!ref $t) {
        my $ctor = Types::Standard->can($t)
          or die "Unknown type name '$t' (expected Type::Tiny or predicate CODE)";
        my $tt   = $ctor->();                     # Type::Tiny object
        my $pred = $tt->compiled_check;           # XS при наличии
        return sub { $pred->($_[0]) ? 1 : 0 };
    }

    # Пользовательский предикат
    if (ref($t) eq 'CODE') {
        return sub { $t->($_[0]) ? 1 : 0 };
    }

    die "Unsupported type spec '$t' (want Type::Tiny, type name, or CODE)";
}

# ---- constructor ----
sub _install_constructor {
    my ($meta, $iface) = @_;
    return if $meta->has_method('new');

    my $ctor = sub {
        my ($class, $impl) = @_;
        die "$class->new: impl (object or class) required" unless defined $impl;

        my $is_obj   = blessed($impl) ? 1 : 0;
        my $impl_pkg = $is_obj ? ref($impl) : $impl;

        # проверим, что все методы реализованы, и закэшируем CODE
        my %call;
        for my $m (keys %{ $IFACE{$class} || {} }) {
            my $code = _resolve_impl_method($impl_pkg, $m)
              or die "$class->new: $impl_pkg does not implement $m()";
            $call{$m} = $code;
        }

        return bless {
            _impl     => $impl,      # объект или имя класса
            _impl_pkg => $impl_pkg,
            _is_obj   => $is_obj,
            _call     => \%call,
        }, $class;
    };

    set_subname("${iface}::new", $ctor);
    $meta->add_method(new => $ctor);
}

sub _resolve_impl_method {
    my ($pkg, $m) = @_;
    no strict 'refs';
    return *{"${pkg}::$m"}{CODE};
}

# ---- wrappers ----
sub _install_wrapper {
    my ($meta, $iface_pkg, $method, $checks) = @_;

    my $wrapper = sub {
        my $self = shift;

        _validate_args_fast(\@_, 0, $checks->{in_checks}, "$iface_pkg->$method");

        my $code = $self->{_call}{$method};
        my @out;
        if (wantarray) {
            @out = $self->{_is_obj} ? $code->($self->{_impl},     @_)
                                     : $code->($self->{_impl_pkg}, @_);
        } else {
            $out[0] = $self->{_is_obj} ? $code->($self->{_impl},     @_)
                                       : $code->($self->{_impl_pkg}, @_);
        }

        if (my $oc = $checks->{out_check}) {
            my $val = wantarray ? ($out[0]) : $out[0];  # PoC: проверяем первый (расширяемо)
            _validate_one($oc, $val, "$iface_pkg->$method return");
        }

        return wantarray ? @out : $out[0];
    };

    set_subname("${iface_pkg}::$method", $wrapper);
    $meta->add_method($method => $wrapper);
}

# ---- валидаторы (быстрые, без копий) ----
sub _validate_args_fast {
    my ($aref, $offset, $preds, $label) = @_;
    my $need = @$preds;
    my $have = @$aref - $offset;
    die "$label: expected $need args, got $have" if $have != $need;

    # specialize для 0/1/2 — дешёвые ветки
    if ($need == 0) { return }
    if ($need == 1) {
        my $v = $aref->[$offset];
        return if $preds->[0]->($v);
        _fail("$label: arg[0] failed", $v);
    }
    elsif ($need == 2) {
        my $v0 = $aref->[$offset];
        my $v1 = $aref->[$offset+1];
        return if $preds->[0]->($v0) && $preds->[1]->($v1);
        _fail("$label: arg[".(!$preds->[0]->($v0)).(!$preds->[1]->($v1))."] failed", undef); # компактно; можно красивее
    }
    else {
        for (my $i=0; $i<$need; $i++) {
            my $v = $aref->[$offset+$i];
            next if $preds->[$i]->($v);
            _fail("$label: arg[$i] failed", $v);
        }
    }
}

sub _validate_one {
    my ($pred, $v, $label) = @_;
    return unless ref $pred eq 'CODE';
    #warn "PRED: $pred";
    return if $pred->($v);
    _fail("$label failed", $v);
}

sub _fail {
    my ($msg, $v) = @_;
    no overloading;
    die defined $v ? "$msg (got $v)" : "$msg";
}

# опционально — геттер реестра (удобно в тестах/дальнейшей склейке)
sub interface_spec {
    my ($class, $name) = @_;
    return $name ? $IFACE{$name} : \%IFACE;
}


sub DESTROY {
    undef %SEEN;
}

1;
