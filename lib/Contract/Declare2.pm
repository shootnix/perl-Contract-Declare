# lib/Contract/Declare2.pm
package Contract::Declare2;

use strict;
use warnings;

use Types::Standard   ();
BEGIN { eval { require Type::Tiny::XS; 1 } }  # ускоряет compiled_check, если установлен

use Attribute::Handlers;
use Class::MOP       ();
use Scalar::Util     qw(blessed);
use Sub::Util        qw(set_subname);
use Type::Registry   ();

# ====== реестры ======
my  %SEEN;                        # временно: iface_pkg -> { method => { args=>[], returns=>[] } }
our %IFACE;                       # итог: iface_pkg -> method -> { in_checks=>[CODE..], out_checks=>[CODE..], check_returns=>bool }
my  %TYPE_CACHE;                  # ключ: "$ctx|$expr" (строка типа/выражение) -> предикат CODE
my  %IMPLEMENTS;                  # class_pkg -> [ iface_pkgs ... ]
my  %DECORATE_IN_PLACE;           # class_pkg -> bool
my  %INTERFACE_MARK;              # pkg -> 1   (только помеченные пакеты считаются интерфейсами)

# ====== ХЕЛПЕРЫ (должны быть выше INIT) ======
sub _norm_list {
    my ($x) = @_;
    return [] unless defined $x;
    return $x  if ref($x) eq 'ARRAY';
    return [$x];
}

# различаем: undef — "не проверяем", [] — "строго void", [..] — список типов
sub _norm_returns {
    my ($x) = @_;
    return undef                                unless defined $x;            # не задано → не проверяем return
    return []             if ref($x) eq 'ARRAY' && @$x == 0;                  # :Returns() → void
    return $x             if ref($x) eq 'ARRAY';                              # список типов
    return [$x];                                                                # одиночный тип
}

# ====== финализация после компиляции всех юнитов ======
INIT {
    # 1) собрать интерфейсы из атрибутов только для помеченных пакетов
    while (my ($pkg, $spec) = each %SEEN) {
        next unless $INTERFACE_MARK{$pkg};
        for my $m (keys %$spec) {
            $spec->{$m}{args}    = _norm_list(   $spec->{$m}{args}    );
            $spec->{$m}{returns} = _norm_returns($spec->{$m}{returns} );
        }
        __PACKAGE__->interface($pkg, $spec);
    }
    %SEEN = ();

    # 2) применить implements-связи
    while (my ($class, $ifaces) = each %IMPLEMENTS) {
        for my $iface (@$ifaces) {
            _ensure_interface_exists($iface);
            _apply_implements($class, $iface);
            _decorate_in_place($class, $iface) if $DECORATE_IN_PLACE{$class};
        }
    }
}

# ====== import: разделяем роли по ключам ======
#   ':interface'                      — интерфейсный пакет (собираем атрибуты)
#   ':impl', implements => 'Iface'    — класс-имплементация (проверка/линк)
#          decorate_in_place => 1     — оборачивать методы класса валидаторами
sub import {
    my ($class, @args) = @_;
    my $caller = caller;

    my @tags = grep { /^:/ } @args;
    @args    = grep { !/^:/ } @args;

    my %opts = @args == 1 && ref($args[0]) eq 'HASH' ? %{ $args[0] } : @args;

    if (grep { $_ eq ':interface' } @tags) {
        $INTERFACE_MARK{$caller} = 1;
    }

    if (grep { $_ eq ':impl' } @tags || exists $opts{implements}) {
        my $impl = delete $opts{implements};
        my @ifaces = ref($impl) eq 'ARRAY' ? @$impl : ($impl);
        push @{ $IMPLEMENTS{$caller} }, grep { defined && length } @ifaces;

        if (delete $opts{decorate_in_place}) {
            $DECORATE_IN_PLACE{$caller} = 1;
        }
    }
}

# ====== атрибуты на методах интерфейса ======
sub UNIVERSAL::Args :ATTR(CODE) {
    my ($pkg, $sym, undef, undef, $data) = @_;
    return unless $INTERFACE_MARK{$pkg};  # учитываем только помеченные пакеты
    my $name = *{$sym}{NAME};
    $SEEN{$pkg}{$name}{args} = $data;     # нормализуем в INIT
}

sub UNIVERSAL::Returns :ATTR(CODE) {
    my ($pkg, $sym, undef, undef, $data) = @_;
    return unless $INTERFACE_MARK{$pkg};
    my $name = *{$sym}{NAME};
    $SEEN{$pkg}{$name}{returns} = $data;  # нормализуем в INIT
}

# ====== объявление интерфейса: компиляция чеков, установка обёрток и new() ======
sub interface {
    my ($class, $iface, $contract) = @_;
    die "interface: need package name" unless defined $iface && length $iface;
    die "interface: need hashref spec" unless ref($contract) eq 'HASH';

    my $meta  = Class::MOP::Class->initialize($iface);
    my $store = ($IFACE{$iface} //= {});

    for my $method (sort keys %$contract) {
        my $spec = $contract->{$method} || {};
        my $args = $spec->{args}    || [];
        my $rets = $spec->{returns};                 # undef | [] | [..]

        my @in_checks = map { _compile_check($_, $iface) } @$args;

        my ($out_checks, $check_returns);
        if (defined $rets) {
            my @ocs = map { _compile_check($_, $iface) } @$rets;  # [] → void
            $out_checks    = \@ocs;
            $check_returns = 1;                                   # проверять арность/типы
        } else {
            $out_checks    = undef;                               # вообще не проверять return
            $check_returns = 0;
        }

        $store->{$method} = {
            in_checks     => \@in_checks,
            out_checks    => $out_checks,     # undef | []
            check_returns => $check_returns,  # bool
        };

        _install_wrapper($meta, $iface, $method, $store->{$method});
    }

    _install_constructor($meta, $iface);
    return $iface;
}

# ====== компиляция типа/выражения → быстрый предикат ======
sub _compile_check {
    my ($t, $ctx_pkg) = @_;   # $ctx_pkg — пакет интерфейса (для Registry и поиска предикатов)

    # 1) Type::Tiny объект
    if (eval { $t->isa('Type::Tiny') }) {
        my $pred = $t->compiled_check;        # ускорится через Type::Tiny::XS
        return sub { $pred->($_[0]) ? 1 : 0 };
    }

    # 2) CODE — пользовательский предикат
    if (ref($t) eq 'CODE') {
        return sub { $t->($_[0]) ? 1 : 0 };
    }

    # 3) GLOB — вдруг передали *func; достанем CODE
    if (ref($t) eq 'GLOB') {
        my $cr = *{$t}{CODE} or die "Glob does not reference a CODE";
        return sub { $cr->($_[0]) ? 1 : 0 };
    }

    # 4) Строка: может быть (а) имя функции-предиката, (б) выражение типа (Maybe[Int]), (в) простое имя типа
    if (!ref $t) {
        my $key = ($ctx_pkg // '') . '|' . $t;
        if (exists $TYPE_CACHE{$key}) {
            return $TYPE_CACHE{$key};
        }

        # 4a) Попробуем трактовать как имя функции-предиката
        {
            my $fq;
            if ($t =~ /::/) {                    # явно квалифицировано
                $fq = $t;
            } else {
                # сначала искать в пакете интерфейса, затем в main::
                $fq = $ctx_pkg ? "${ctx_pkg}::$t" : $t;
            }

            no strict 'refs';
            if (my $cr = *{"${fq}"}{CODE}) {
                return $TYPE_CACHE{$key} = sub { $cr->($_[0]) ? 1 : 0 };
            }
            if (my $cr2 = *{"main::$t"}{CODE}) {
                return $TYPE_CACHE{$key} = sub { $cr2->($_[0]) ? 1 : 0 };
            }
        }

        # 4b) Параметризованные и составные типы: через Type::Registry
        {
            my $reg = Type::Registry->for_class( $ctx_pkg // 'main' );
            $reg->add_types('Types::Standard');              # гарантируем базовые типы

            if (my $tt = $reg->lookup($t)) {                 # понимает Maybe[Int], ArrayRef[Int], Tuple[Int,Str], ...
                my $pred = $tt->compiled_check;
                return $TYPE_CACHE{$key} = sub { $pred->($_[0]) ? 1 : 0 };
            }
        }

        # 4c) Фоллбек: простые имена из Types::Standard
        if (my $ctor = Types::Standard->can($t)) {
            my $tt   = $ctor->();
            my $pred = $tt->compiled_check;
            return $TYPE_CACHE{$key} = sub { $pred->($_[0]) ? 1 : 0 };
        }

        die "Unknown type or predicate '$t'";
    }

    die "Unsupported type spec '$t' (want Type::Tiny, type name/expression, or CODE)";
}

# ====== конструктор new($impl) — кэшируем методы реализации ======
sub _install_constructor {
    my ($meta, $iface) = @_;
    return if $meta->has_method('new');

    my $ctor = sub {
        my ($class, $impl) = @_;
        die "$class->new: impl (object or class) required" unless defined $impl;

        my $is_obj   = blessed($impl) ? 1 : 0;
        my $impl_pkg = $is_obj ? ref($impl) : $impl;

        my %call;
        for my $m (keys %{ $IFACE{$class} || {} }) {
            my $code = _resolve_impl_method($impl_pkg, $m)
              or die "$class->new: $impl_pkg does not implement $m()";
            $call{$m} = $code;
        }

        return bless {
            _impl     => $impl,
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

# ====== адаптер-метод в интерфейсном классе ======
sub _install_wrapper {
    my ($meta, $iface_pkg, $method, $checks) = @_;

    my $wrapper = sub {
        my $self = shift;

        _validate_args_fast(\@_, 0, $checks->{in_checks}, "$iface_pkg->$method");

        my $code = $self->{_call}{$method};
        my @out;
        if (wantarray) {
            @out = $self->{_is_obj} ? $code->($self->{_impl},      @_)
                                     : $code->($self->{_impl_pkg},  @_);
        } else {
            $out[0] = $self->{_is_obj} ? $code->($self->{_impl},      @_)
                                       : $code->($self->{_impl_pkg},  @_);
        }

        if ($checks->{check_returns}) {
            my $ocs  = $checks->{out_checks};         # undef уже отфильтрован
            my @vals = wantarray ? @out : @out ? ($out[0]) : ();
            my $need = @$ocs;                         # 0 → строго void

            die "$iface_pkg->$method return: expected $need values, got ".@vals
                if @vals != $need;

            for my $i (0..$#$ocs) {
                _validate_one($ocs->[$i], $vals[$i], "$iface_pkg->$method return\[$i\]");
            }
        }

        return wantarray ? @out : $out[0];
    };

    set_subname("${iface_pkg}::$method", $wrapper);
    $meta->add_method($method => $wrapper);
}

# ====== быстрая валидация аргументов ======
sub _validate_args_fast {
    my ($aref, $offset, $preds, $label) = @_;
    my $need = @$preds;
    my $have = @$aref - $offset;
    die "$label: expected $need args, got $have" if $have != $need;

    if ($need == 0) { return }

    if ($need == 1) {
        my $v = $aref->[$offset];
        return if $preds->[0]->($v);
        _fail("$label: arg[0] failed", $v);
    }
    elsif ($need == 2) {
        my $v0 = $aref->[$offset];
        my $v1 = $aref->[$offset+1];
        my $ok0 = $preds->[0]->($v0);
        my $ok1 = $preds->[1]->($v1);
        return if $ok0 && $ok1;
        _fail("$label: arg[".($ok0?'':'0').($ok1?'':'1')."] failed", $ok0 ? $v1 : $v0);
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
    return if $pred->($v);
    _fail("$label failed", $v);
}

sub _fail {
    my ($msg, $v) = @_;
    no overloading;
    die defined $v ? "$msg (got $v)" : "$msg";
}

# ====== implements: проверки + Role::Tiny, опционально decorate_in_place ======
sub _ensure_interface_exists {
    my ($iface) = @_;
    die "Unknown interface $iface" unless exists $IFACE{$iface};
}

sub _apply_implements {
    my ($class, $iface) = @_;

    # 1) строгая проверка наличия методов
    my $spec = $IFACE{$iface} || {};
    for my $m (keys %$spec) {
        my $code = _resolve_impl_method($class, $m);
        die "$class must implement $m() for interface $iface"
            unless $code;
    }

    # 2) Role::Tiny (если установлен): создаём роль iface::Role с requires и применяем
    if (eval { require Role::Tiny; 1 }) {
        my $role = "${iface}::Role";
        unless (_role_already_created($role)) {
            my @req = sort keys %$spec;
            my $src = "package $role; use Role::Tiny; requires qw(" . join(' ', @req) . "); 1;";
            eval $src or die "Failed to create role $role: $@";
        }
        Role::Tiny->apply_roles_to_package($class, $role);
    }
}

sub _decorate_in_place {
    my ($class, $iface) = @_;
    my $spec = $IFACE{$iface} || {};
    my $meta = Class::MOP::Class->initialize($class);

    for my $m (keys %$spec) {
        next unless $meta->has_method($m);
        my $orig   = $meta->get_method($m)->body;
        my $checks = $spec->{$m};

        my $wrapped = sub {
            _validate_args_fast(\@_, 0, $checks->{in_checks}, "$class->$m");
            my @out = wantarray ? $orig->(@_) : scalar $orig->(@_);
            if ($checks->{check_returns}) {
                my $ocs  = $checks->{out_checks};
                my @vals = wantarray ? @out : @out ? ($out[0]) : ();
                my $need = @$ocs;
                die "$class->$m return: expected $need values, got ".@vals
                    if @vals != $need;
                for my $i (0..$#$ocs) {
                    _validate_one($ocs->[$i], $vals[$i], "$class->$m return\[$i\]");
                }
            }
            return wantarray ? @out : $out[0];
        };

        set_subname("${class}::$m", $wrapped);
        $meta->add_method($m => $wrapped);
    }
}

sub _role_already_created {
    my ($role) = @_;
    no strict 'refs';
    return defined *{"${role}::"}{HASH};  # пакет уже существует
}

# ====== утилиты ======
sub interface_spec {
    my ($class, $name) = @_;
    return $name ? $IFACE{$name} : \%IFACE;
}

1;
