package Contract::Declare2;

use strict;
use warnings;

use Types::Standard   ();
BEGIN { eval { require Type::Tiny::XS; 1 } }  # speeds up compiled_check if installed

use Attribute::Handlers;
use Scalar::Util     qw(blessed);
use Sub::Util        qw(set_subname);

# ====== registries / state ======
my  %SEEN;                        # temp: iface_pkg -> { method => { args=>[], returns=>[] } }
our %IFACE;                       # final: iface_pkg -> method -> { in_checks=>[CODE..], out_checks=>[CODE..], check_returns=>bool }
my  %TYPE_CACHE;                  # key: "$ctx|$expr" -> predicate CODE
my  %IMPLEMENTS;                  # class_pkg -> [ iface_pkgs ... ]
my  %INTERFACE_MARK;              # pkg -> 1 (which packages are treated as interfaces)

# accelerators
my  %ADAPTER_CACHE;               # {$iface}{$impl_pkg|$is_obj} = adapter_pkg
my  $ADAPTER_SEQ = 0;             # unique names for adapter packages
my  %IFACE_METHOD_LIST;           # {$iface} = [ method1, method2, ... ]
my  %VTABLE_CACHE;                # {$iface}{$impl_pkg} = { method => CODE, ... }

# ====== helpers ======
sub _norm_list {
    my ($x) = @_;
    return [] unless defined $x;
    return $x  if ref($x) eq 'ARRAY';
    return [$x];
}

# distinguish: undef — "do not validate", [] — "strict void", [..] — list of types/predicates
sub _norm_returns {
    my ($x) = @_;
    return undef                                unless defined $x;            # not specified → do not validate return
    return []             if ref($x) eq 'ARRAY' && @$x == 0;                  # :Returns() → void
    return $x             if ref($x) eq 'ARRAY';
    return [$x];
}

# ====== finalization ======
INIT {
    # 1) build interfaces from attributes only for marked packages
    while (my ($pkg, $spec) = each %SEEN) {
        next unless $INTERFACE_MARK{$pkg};
        for my $m (keys %$spec) {
            $spec->{$m}{args}    = _norm_list(   $spec->{$m}{args}    );
            $spec->{$m}{returns} = _norm_returns($spec->{$m}{returns} );
        }
        __PACKAGE__->interface($pkg, $spec);
    }
    %SEEN = ();

    # 2) apply implements-relations (strict method presence check)
    while (my ($class, $ifaces) = each %IMPLEMENTS) {
        for my $iface (@$ifaces) {
            _ensure_interface_exists($iface);
            _apply_implements($class, $iface);
        }
    }
}

# ====== import: tags ======
#   ':interface'                      — interface package (collect attributes)
#   ':impl', implements => 'Iface'    — implementation class (check/link)
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
    }
}

# ====== attributes (no RAWDATA, no composite types) ======
sub UNIVERSAL::Args :ATTR(CODE) {
    my ($pkg, $sym, undef, undef, $data) = @_;
    return unless $INTERFACE_MARK{$pkg};
    my $name = *{$sym}{NAME};
    $SEEN{$pkg}{$name}{args} = $data;     # scalar | arrayref | undef — normalized in INIT
}

sub UNIVERSAL::Returns :ATTR(CODE) {
    my ($pkg, $sym, undef, undef, $data) = @_;
    return unless $INTERFACE_MARK{$pkg};
    my $name = *{$sym}{NAME};
    $SEEN{$pkg}{$name}{returns} = $data;  # scalar | arrayref | undef — normalized in INIT
}

# ====== interface declaration ======
sub interface {
    my ($class, $iface, $contract) = @_;
    die "interface: need package name" unless defined $iface && length $iface;
    die "interface: need hashref spec" unless ref($contract) eq 'HASH';

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
            $check_returns = 1;                                   # validate arity/types
        } else {
            $out_checks    = undef;                               # do not validate return at all
            $check_returns = 0;
        }

        $store->{$method} = {
            in_checks     => \@in_checks,
            out_checks    => $out_checks,     # undef | []
            check_returns => $check_returns,  # bool
        };
    }

    # cache sorted interface method list
    $IFACE_METHOD_LIST{$iface} = [ sort keys %{ $IFACE{$iface} } ];

    _install_constructor_fast($iface);   # fast constructor/adapter
    return $iface;
}

# ====== compile type/expression → fast predicate ======
# Supports:
#  - Type::Tiny object (e.g., Types::Standard::Str())
#  - CODE predicate
#  - GLOB with CODE
#  - Simple type name from Types::Standard ('Str','Int',...)
#  - Function name predicate (in $ctx_pkg:: or main::)
sub _compile_check {
    my ($t, $ctx_pkg) = @_;

    # Type::Tiny object
    if (eval { $t->isa('Type::Tiny') }) {
        return $t->compiled_check;        # no extra wrapper
    }

    # CODE — user predicate
    if (ref($t) eq 'CODE') {
        return $t;
    }

    # GLOB — *func
    if (ref($t) eq 'GLOB') {
        my $cr = *{$t}{CODE} or die "Glob does not reference a CODE";
        return $cr;
    }

    # String
    if (!ref $t) {
        my $key = ($ctx_pkg // '') . '|' . $t;
        if (exists $TYPE_CACHE{$key}) { return $TYPE_CACHE{$key} }

        # first try as function name predicate
        {
            (my $name = $t) =~ s/^\s+|\s+$//g;
            no strict 'refs';
            my $fq = ($name =~ /::/) ? $name : ($ctx_pkg ? "${ctx_pkg}::$name" : $name);
            if (my $cr = *{"$fq"}{CODE}) {
                return $TYPE_CACHE{$key} = $cr;
            }
            if (my $cr2 = *{"main::$name"}{CODE}) {
                return $TYPE_CACHE{$key} = $cr2;
            }
        }

        # Simple type from Types::Standard
        if (my $ctor = Types::Standard->can($t)) {
            my $tt = $ctor->();
            return $TYPE_CACHE{$key} = $tt->compiled_check;
        }

        die "Unknown type or predicate '$t'";
    }

    die "Unsupported type spec '$t' (want Type::Tiny, type name, or CODE)";
}

# ====== fast constructor/adapter (no MOP/hash/branches) ======
sub _install_constructor_fast {
    my ($iface) = @_;

    no strict 'refs';
    return if defined &{"${iface}::new"};

    *{"${iface}::new"} = sub {
        my ($class, $impl) = @_;
        die "$class->new: impl (object or class) required" unless defined $impl;

        my $is_obj   = blessed($impl) ? 1 : 0;
        my $impl_pkg = $is_obj ? ref($impl) : $impl;

        # adapter package cache keyed by (iface, impl_pkg, is_obj)
        my $cache_key = "$impl_pkg|$is_obj";
        my $adp_pkg   = $ADAPTER_CACHE{$class}{$cache_key};

        unless ($adp_pkg) {
            # 1) get/build vtable for (iface, impl_pkg)
            my $v = ($VTABLE_CACHE{$class}{$impl_pkg} //= do {
                my %tmp;
                for my $m (@{ $IFACE_METHOD_LIST{$class} }) {
                    my $code = *{"${impl_pkg}::$m"}{CODE}
                      or die "$class->new: $impl_pkg does not implement $m()";
                    $tmp{$m} = $code;
                }
                \%tmp
            });

            # 2) create adapter package and install methods
            my $san = $impl_pkg; $san =~ s/::/__/g;
            $adp_pkg = "${class}::__Adapter__::$san\__$is_obj\__" . ($ADAPTER_SEQ++);

            if ($is_obj) {
                # object variant: $_[0] = $_[0][0];
                for my $m (@{ $IFACE_METHOD_LIST{$class} }) {
                    my $checks = $IFACE{$class}{$m};
                    my $preds  = $checks->{in_checks};
                    my $outs   = $checks->{check_returns} ? $checks->{out_checks} : undef;
                    my $code   = $v->{$m};
                    *{"${adp_pkg}::${m}"} = $outs
                        ? _make_wrapped_obj_with_returns($class, $m, $preds, $outs, $code)
                        : _make_wrapped_obj_fast      ($class, $m, $preds,         $code);
                }
            } else {
                # class variant: $_[0] = $impl_pkg;
                for my $m (@{ $IFACE_METHOD_LIST{$class} }) {
                    my $checks = $IFACE{$class}{$m};
                    my $preds  = $checks->{in_checks};
                    my $outs   = $checks->{check_returns} ? $checks->{out_checks} : undef;
                    my $code   = $v->{$m};
                    *{"${adp_pkg}::${m}"} = $outs
                        ? _make_wrapped_class_with_returns($class, $m, $preds, $outs, $code, $impl_pkg)
                        : _make_wrapped_class_fast      ($class, $m, $preds,         $code, $impl_pkg);
                }
            }

            $ADAPTER_CACHE{$class}{$cache_key} = $adp_pkg;
        }

        # 3) bless — object keeps impl only in object case
        return $is_obj ? bless [ $impl ], $adp_pkg
                       : bless [],        $adp_pkg;
    };
}

# ====== wrappers: object ======
sub _make_wrapped_obj_fast {
    my ($iface, $m, $preds, $code) = @_;

    return sub {
        my $argc = @_-1;
        my $need = @$preds;
        die "$iface->$m: expected $need args, got $argc" if $argc != $need;

        for (my $i=0; $i<$need; $i++) {
            $preds->[$i]->($_[$i+1]) or _fail("$iface->$m: arg[$i] failed", $_[$i+1]);
        }

        $_[0] = $_[0][0];  # invocant = real implementation object
        goto &$code;
    };
}

sub _make_wrapped_obj_with_returns {
    my ($iface, $m, $preds, $outs, $code) = @_;

    return sub {
        my $argc = @_-1;
        my $need = @$preds;
        die "$iface->$m: expected $need args, got $argc" if $argc != $need;

        for (my $i=0; $i<$need; $i++) {
            $preds->[$i]->($_[$i+1]) or _fail("$iface->$m: arg[$i] failed", $_[$i+1]);
        }

        $_[0] = $_[0][0];

        if (wantarray) {
            my @r = $code->(@_);
            my $need_r = @$outs;
            die "$iface->$m return: expected $need_r values, got ".@r if @r != $need_r;
            for my $j (0..$#$outs) { $outs->[$j]->($r[$j]) or _fail("$iface->$m return\[$j\]", $r[$j]) }
            return @r;
        } else {
            my $r = $code->(@_);
            my $need_r = @$outs;
            my $got    = defined wantarray ? 1 : 0;
            die "$iface->$m return: expected $need_r values, got $got" if $got != $need_r;
            $outs->[0]->($r) or _fail("$iface->$m return\[0]", $r) if $need_r;
            return $r;
        }
    };
}

# ====== wrappers: class ======
sub _make_wrapped_class_fast {
    my ($iface, $m, $preds, $code, $impl_pkg) = @_;

    return sub {
        my $argc = @_-1;
        my $need = @$preds;
        die "$iface->$m: expected $need args, got $argc" if $argc != $need;

        for (my $i=0; $i<$need; $i++) {
            $preds->[$i]->($_[$i+1]) or _fail("$iface->$m: arg[$i] failed", $_[$i+1]);
        }

        $_[0] = $impl_pkg;  # invocant = implementation class name
        goto &$code;
    };
}

sub _make_wrapped_class_with_returns {
    my ($iface, $m, $preds, $outs, $code, $impl_pkg) = @_;

    return sub {
        my $argc = @_-1;
        my $need = @$preds;
        die "$iface->$m: expected $need args, got $argc" if $argc != $need;

        for (my $i=0; $i<$need; $i++) {
            $preds->[$i]->($_[$i+1]) or _fail("$iface->$m: arg[$i] failed", $_[$i+1]);
        }

        $_[0] = $impl_pkg;

        if (wantarray) {
            my @r = $code->(@_);
            my $need_r = @$outs;
            die "$iface->$m return: expected $need_r values, got ".@r if @r != $need_r;
            for my $j (0..$#$outs) { $outs->[$j]->($r[$j]) or _fail("$iface->$m return\[$j\]", $r[$j]) }
            return @r;
        } else {
            my $r = $code->(@_);
            my $need_r = @$outs;
            my $got    = defined wantarray ? 1 : 0;
            die "$iface->$m return: expected $need_r values, got $got" if $got != $need_r;
            $outs->[0]->($r) or _fail("$iface->$m return\[0]", $r) if $need_r;
            return $r;
        }
    };
}

# ====== implements (strict method presence check) ======
sub _ensure_interface_exists {
    my ($iface) = @_;
    die "Unknown interface $iface" unless exists $IFACE{$iface};
}

sub _apply_implements {
    my ($class, $iface) = @_;

    my $spec = $IFACE{$iface} || {};
    for my $m (keys %$spec) {
        no strict 'refs';
        my $code = *{"${class}::$m"}{CODE};
        die "$class must implement $m() for interface $iface" unless $code;
    }

    # keep as no-op; Role::Tiny can be added separately if desired
}

# ====== validation / errors ======
sub _fail {
    my ($msg, $v) = @_;
    no overloading;
    die defined $v ? "$msg (got $v)" : "$msg";
}

# ====== utilities ======
sub interface_spec {
    my ($class, $name) = @_;
    return $name ? $IFACE{$name} : \%IFACE;
}

1;

