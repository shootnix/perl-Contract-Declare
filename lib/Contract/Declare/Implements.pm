use v5.32;
use warnings;

package Contract::Declare::Implements {
    use Contract::Declare::Interface ();
    use Carp qw/croak/;
    use Module::Load;

    use Type::Registry;
    use Type::Parser qw/eval_type/;

    my $IMP = {};

    my $reg = Type::Registry->for_me;
    $reg->add_types("Types::Standard");


    my sub validate {
        my ($pkg, $sub_name, $args, $expects) = @_;

        scalar @$args == scalar @$expects or croak "panic: number of expecting parameters doesn't match for $pkg" . '::' . $sub_name . '()';

        for (my $i=0; $i< @$args; $i++) {
            my $param = $args->[$i];
            my $str_type = $expects->[$i];
            my $type = eval_type($str_type, $reg);
            $type->check($param) or croak "panic: types mismatch: $str_type";
        }
    }

    sub import {
        my ($class, @iface_names) = @_;
        my $caller = caller;

        my $registry = Contract::Declare::Interface::get_registry();

        $IMP->{$caller} = [];

        for my $iface_name (@iface_names) {
            $registry->{$iface_name} or croak "panic: can't find interface `$iface_name`" . " (did you forget to `use` the module that declares it?)";
            push $IMP->{$caller}->@*, $iface_name;
        }
    }

    INIT {
        my $registry = Contract::Declare::Interface::get_registry();
        no strict 'refs';
        no warnings 'redefine';
        for my $pkg (keys %$IMP) {
            load $pkg;
            for my $iface_name ($IMP->{$pkg}->@*) {
                for my $sub_name (keys $registry->{$iface_name}->%*) {
                    my $sub = $pkg->can($sub_name) or croak "$pkg donesn't implement interface `$iface_name`: can't do the `$sub_name` sub";
                    *{"${pkg}::$sub_name"} = sub {
                        validate($pkg, $sub_name, \@_, $registry->{$iface_name}{$sub_name}{EXPECTS});
                        my @res = $sub->(@_);
                        validate($pkg, $sub_name, \@res, $registry->{$iface_name}{$sub_name}{RETURNS});
                        return wantarray ? @res : $res[0];
                    };
                }
            }
        }
    }
}

1;

=encoding utf8

=head1 NAME

Contract::Declare::Implements - attach a class to an interface and enforce it at runtime

=head1 SYNOPSIS

    package My::Reader {
        use Contract::Declare::Interface name => 'Reader';

        sub read :Expects(Object, Str) :Returns(Str);
    }

    package My::JSONReader {
        use My::Reader;
        use Contract::Declare::Implements qw/Reader/;

        sub new  { return bless {}, shift }
        sub read {
            my ($self, $filename) = @_;
            ...
            return $contents;
        }
    }

    my $reader = My::JSONReader->new;
    $reader->read('data.json');   # arguments and return value are validated

=head1 DESCRIPTION

C<Contract::Declare::Implements> declares that the calling package
implements one or more interfaces previously declared with
L<Contract::Declare::Interface>, and arranges for every method required by
those interfaces to be wrapped with a runtime type check: arguments are
validated against the interface's C<:Expects> types before the real method
runs, and its return value is validated against C<:Returns> before it is
handed back to the caller.

=head1 USAGE

=head2 use Contract::Declare::Implements qw/InterfaceName ... /;

Declares that the calling package implements each named interface. Each
interface must already be registered (i.e. its declaring module must
already be C<use>d) - dies with C<panic: can't find interface
`$iface_name` (did you forget to `use` the module that declares it?)>
otherwise.

This only records the intent; the actual method wrapping happens later,
in an C<INIT> block (see L</"HOW AND WHEN METHODS ARE WRAPPED"> below), once
every required method is guaranteed to exist.

=head2 What gets checked, and when

For every sub required by an implemented interface, the class's own sub of
the same name is replaced with a wrapper that:

=over 4

=item 1. validates C<@_> (the invocant plus all arguments) against the
interface's C<:Expects> types, dying with C<panic: number of expecting
parameters doesn't match for Pkg::sub_name()> if the argument count
differs, or C<panic: types mismatch: $type> if any value fails its type
check;

=item 2. calls the original implementation;

=item 3. validates the returned value(s) against C<:Returns> the same way;

=item 4. returns the result to the caller (a list in list context, the
first value in scalar context).

=back

If the class does not define a sub required by the interface at all, this
is caught before any wrapping happens, with C<panic: $pkg donesn't
implement interface `$iface_name`: can't do the `$sub_name` sub>.

=head1 HOW AND WHEN METHODS ARE WRAPPED

Wrapping happens in a single C<INIT> block defined in this module, which
Perl runs once, after the entire program has finished compiling. This
means a class only gets its contract enforced if it (or something that
loads it) was reached via a top-level C<use> - directly, or transitively
through another module's C<use> - before the program starts running.

A class loaded afterwards, at runtime, via C<require Some::Class> or
similar dynamic loading, is B<not> retroactively wrapped: its methods run
exactly as written, with no argument or return-value validation, and
without any error or warning to indicate the contract was skipped. Design
around this by preferring static C<use> for any class you want contract
enforcement on.

=head1 SEE ALSO

L<Contract::Declare>, L<Contract::Declare::Interface>, L<Types::Standard>,
L<Type::Registry>

=cut