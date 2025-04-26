package Contract::Declare;

use v5.32;
use Exporter 'import';
use Role::Tiny ();
use Scalar::Util qw(blessed);
use Carp;

our @EXPORT = qw(contract interface method returns);

my $CHECK         = $ENV{I_CHECK_TYPES};
my $KEEP_CONTRACT = $ENV{I_KEEP_CONTRACT};

my $CURRENT_PKG;
my %REGISTRY;

sub contract {
    ($CURRENT_PKG, my $block) = @_;
    $block->();
    _build_contract($CURRENT_PKG, $REGISTRY{$CURRENT_PKG});
    delete $REGISTRY{$CURRENT_PKG} unless $KEEP_CONTRACT;
}

sub interface (&) { shift }
sub returns       { [ @_ ] }

sub method {
    my ($name, @parts) = @_;
    my (@in, $out);

    for my $p (@parts) {
        if (ref($p) eq 'ARRAY') {
            $out = $p;
            last;
        }
        push @in, $p;
    }

    $REGISTRY{$CURRENT_PKG}{$name} = [ \@in, $out ];
}

sub _build_contract {
    my ($pkg, $contract) = @_;

    no strict 'refs';

    *{"${pkg}::new"} = sub {
        my ($class, $impl) = @_;
        my %cache;

        for my $method (keys %$contract) {
            my $code = $impl->can($method);
            croak "impl does not implement $method" unless $code;
            $cache{$method} = $code;
        }

        bless {
            _impl  => $impl,
            _cache => \%cache,
        }, $pkg;
    };

    for my $method (keys %$contract) {
        my ($in_rules, $out_rules) = @{$contract->{$method}};
        my @in_checks  = map { $_->compiled_check } @$in_rules;
        my @out_checks = map { $_->compiled_check } @$out_rules;

        *{"${pkg}::$method"} = sub {
            my ($self, @args) = @_;

            if ($CHECK) {
                _validate(\@args, \@in_checks, "$pkg\::$method args");
            }

            my @res = $self->{_cache}{$method}->($self->{_impl}, @args);

            if ($CHECK) {
                _validate(\@res, \@out_checks, "$pkg\::$method return");
            }

            return wantarray ? @res : $res[0];
        };
    }

    Role::Tiny->make_role($pkg);
    $Role::Tiny::INFO{$pkg}{requires} = [ sort keys %$contract ];

    use strict 'refs';
}

sub _validate {
    my ($values, $checkers, $label) = @_;

    return if @$checkers == 0;

    croak "$label: wrong arg count" if @$values != @$checkers;

    for (my $i = 0; $i < @$checkers; $i++) {
        next if $checkers->[$i]->($values->[$i]);
        croak "$label: argument #$i failed check";
    }
}

1;