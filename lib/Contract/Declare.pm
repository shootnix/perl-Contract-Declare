package Contract::Declare;

use v5.14;
use warnings;

our $VERSION = '0.01';

1;

=encoding utf8

=head1 NAME

Contract::Declare - design-by-contract interfaces with runtime type checking

=head1 SYNOPSIS

    # 1. Declare an interface: a package name plus a set of subs whose
    #    parameter and return types are the contract.
    package My::Reader {
        use Contract::Declare::Interface name => 'Reader';

        sub read :Expects(Object, Str) :Returns(Str);
    }

    # 2. Implement it. Every sub required by the interface must exist;
    #    Contract::Declare wraps each one with a runtime type check.
    package My::JSONReader {
        use My::Reader;
        use Contract::Declare::Implements qw/Reader/;

        sub new { return bless {}, shift }

        sub read {
            my ($self, $filename) = @_;
            ...
            return $file_contents;
        }
    }

    # 3. Use it. Arguments and return values are validated on every call.
    my $reader = My::JSONReader->new;
    my $text   = $reader->read('data.json');   # ok
    $reader->read('data.json', 'oops');        # dies: wrong number of parameters
    $reader->read([]);                         # dies: types mismatch: Str

=head1 DESCRIPTION

C<Contract::Declare> is a small design-by-contract toolkit for Perl. It lets
you declare an B<interface> - a named set of method signatures - separately
from any class that implements it, and it enforces those signatures at
runtime: every call to an implementing method has its arguments and its
return value checked against the declared types before the caller ever
sees the result.

The distribution is split into two collaborating modules, and this module
(C<Contract::Declare> itself) exists only to hold this overview - it has no
exported symbols and nothing to C<use> from it directly.

=over 4

=item * L<Contract::Declare::Interface>

Declares an interface: a name, and a set of subs annotated with
C<:Expects(...)> and C<:Returns(...)> attributes describing the types of
their parameters (including the invocant) and their return value.

=item * L<Contract::Declare::Implements>

Marks a class as implementing one or more interfaces. Every sub required
by those interfaces must already exist in the class; C<Contract::Declare>
replaces each one with a wrapper that validates arguments on the way in
and the return value on the way out, using L<Types::Standard> type names.

=back

=head1 HOW IT WORKS

Interfaces are recorded in a process-wide registry keyed by interface name
(see L<Contract::Declare::Interface/get_registry>). When a class does

    use Contract::Declare::Implements qw/SomeInterface/;

it registers itself as an implementor of C<SomeInterface>. At the end of
compilation (Perl's C<INIT> phase, i.e. once every C<use> in the program
has run), C<Contract::Declare::Implements> walks every registered
implementor and, for each sub required by its interface(s):

=over 4

=item 1. confirms the class actually defines that sub (via C<< $class->can(...) >>);

=item 2. replaces it with a wrapper that validates C<@_> against C<:Expects>,
calls the original implementation, validates the result against
C<:Returns>, and then returns it to the caller.

=back

Type names in C<:Expects>/C<:Returns> are resolved with L<Type::Parser>
against a L<Type::Registry> preloaded with L<Types::Standard>, so any
standard type - C<Str>, C<Int>, C<Num>, C<Bool>, C<Object>, C<HashRef>,
C<ArrayRef>, C<Maybe[Str]>, C<Any>, and so on - can be used out of the box.

=head1 CAVEATS

=over 4

=item * Implementing classes must be compiled before C<INIT> time

Contract enforcement is wired up in an C<INIT> block, which only fires once,
after the whole program has finished compiling. A class loaded via a
top-level C<use> (directly or indirectly) gets wrapped correctly. A class
loaded later at runtime via C<require> (lazy-loading, plugin systems, etc.)
is silently B<not> wrapped: its methods run unmodified, with no argument or
return-value checking at all, and no warning is issued.

=item * C<:Expects>/C<:Returns> are global attributes

C<Contract::Declare::Interface> installs its C<:Expects> and C<:Returns>
attribute handlers into C<UNIVERSAL>, which makes them visible to every
package in the process once the module has been loaded once, not just to
packages that declare an interface. Attaching either attribute to a sub in
a package that never called
C<< use Contract::Declare::Interface name => ... >> raises a "panic: can't
find any interface implemented in ..." error.

=item * Interface names are unique per process

Two interfaces cannot share a name; the second C<use Contract::Declare::Interface
name => 'Same'> dies immediately.

=item * Only L<Types::Standard> type names are recognised

C<:Expects>/C<:Returns> are checked against a L<Type::Registry> that only
has L<Types::Standard> loaded. Type libraries from your own application are
not available unless you extend the registry yourself.

=item * Contract violations always C<croak>

There is no soft-fail mode; wrap calls in C<eval>/L<Try::Tiny> if you need
to recover from a contract violation instead of dying.

=back

=head1 SEE ALSO

L<Contract::Declare::Interface>, L<Contract::Declare::Implements>,
L<Type::Tiny>, L<Types::Standard>, L<Attribute::Handlers>

=head1 AUTHOR

shootnix E<lt>shootnix@gmail.comE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
