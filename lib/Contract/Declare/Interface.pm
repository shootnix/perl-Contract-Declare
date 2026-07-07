use v5.14;
use warnings;

package Contract::Declare::Interface {
    use Attribute::Handlers;
    use Carp qw/croak/;

    my $REGISTRY = {};
    my $PKG_IFACE_MAP = {};

    sub import {
        my ($class, %args) = @_;
        my $caller = caller;

        my $interface_name = $args{name} // $caller;
        croak "panic: interface `$interface_name` already defined" 
            if $REGISTRY->{$interface_name};
        
        $REGISTRY->{$interface_name} = {};
        $PKG_IFACE_MAP->{$caller} = $interface_name;
    }

    sub UNIVERSAL::Expects :ATTR(CODE,BEGIN) {
        my ($pkg, $sym, undef, undef, $data, undef, $file, $line) = @_;
        my $sub_name = *{$sym}{NAME};
        my $iface_name = $PKG_IFACE_MAP->{$pkg} or croak "panic: can't find any interface implemented in $pkg";
        $REGISTRY->{$iface_name} or croak "panic: can't find interface `$iface_name`";
        if ($REGISTRY->{$iface_name}{$sub_name}) {
            ! exists $REGISTRY->{$iface_name}{$sub_name}{EXPECTS} 
                or croak "panic: already defined sub `$sub_name` for interface `$iface_name`";
            
            $REGISTRY->{$iface_name}{$sub_name}{EXPECTS} = $data;
        }
        else {
            $REGISTRY->{$iface_name}{$sub_name} = {
                PKG     => $pkg,
                FILE    => $file,
                LINE    => $line,
                EXPECTS => $data,
            };
        }
    }

    sub UNIVERSAL::Returns :ATTR(CODE,BEGIN) {
        my ($pkg, $sym, undef, undef, $data, undef, $file, $line) = @_;

        my $sub_name = *{$sym}{NAME};
        my $iface_name = $PKG_IFACE_MAP->{$pkg} or croak "panic: can't find any interface implemented in $pkg";
        $REGISTRY->{$iface_name} or croak "panic: can't find interface `$iface_name`";

        if ($REGISTRY->{$iface_name}{$sub_name}) {
            ! exists $REGISTRY->{$iface_name}{$sub_name}{RETURNS} 
                or croak "panic: already defined sub `$sub_name` for interface `$iface_name`";
            
            $REGISTRY->{$iface_name}{$sub_name}{RETURNS} = $data;
        }
        else {
            $REGISTRY->{$iface_name}{$sub_name} = {
                PKG     => $pkg,
                FILE    => $file,
                LINE    => $line,
                RETURNS => $data,
            };
        }
    }

    sub get_registry {
        return $REGISTRY;
    }
}

1;

=encoding utf8

=head1 NAME

Contract::Declare::Interface - declare a named interface with typed method signatures

=head1 SYNOPSIS

    package My::Reader {
        use Contract::Declare::Interface name => 'Reader';

        sub read  :Expects(Object, Str) :Returns(Str);
        sub close :Expects(Object)      :Returns(Bool);
    }

=head1 DESCRIPTION

C<Contract::Declare::Interface> lets a package declare an B<interface>: a
name, plus a set of sub signatures describing the types of their
parameters and return value. Declaring an interface does not implement
any behaviour - the subs are left as forward declarations (no body). See
L<Contract::Declare::Implements> for how a class attaches real behaviour
to an interface and gets it enforced at runtime.

=head1 USAGE

=head2 use Contract::Declare::Interface name => $interface_name;

Registers the calling package as the home of a new interface. If C<name>
is omitted, the interface is named after the calling package.

    package My::Reader {
        use Contract::Declare::Interface;      # interface name: 'My::Reader'
    }

Dies with C<panic: interface `$interface_name` already defined> if another
package has already registered an interface under that name - interface
names are unique for the lifetime of the process.

=head2 sub NAME :Expects(Type, Type, ...) :Returns(Type, ...);

Declares a required method named C<NAME> as part of the interface. Both
attributes take a comma-separated list of type names understood by
L<Types::Standard> (via L<Type::Parser>/L<Type::Registry>), for example
C<Str>, C<Int>, C<Num>, C<Bool>, C<Object>, C<HashRef>, C<ArrayRef>,
C<Maybe[Str]>, C<Any>.

C<:Expects> describes every element of C<@_> the implementing method will
receive, B<including the invocant> - so an instance method that takes one
extra string argument is typically written as C<:Expects(Object, Str)>.
C<:Returns> describes the value(s) the method must return.

The sub is declared without a body (a forward declaration); a package
using C<Contract::Declare::Interface> is meant to contain nothing but a
list of these declarations.

Both attributes may be applied to the same sub in either order, but each
may only be given once per sub - applying C<:Expects> (or C<:Returns>)
twice to the same sub name dies with C<panic: already defined sub `NAME`
for interface `IFACE`>.

Because C<:Expects>/C<:Returns> are implemented as attribute handlers
installed into C<UNIVERSAL>, they become available to B<every> package in
the process as soon as C<Contract::Declare::Interface> has been loaded
once - not only to packages that declared an interface themselves. Using
either attribute in a package that never called
C<use Contract::Declare::Interface> dies with C<panic: can't find any
interface implemented in $pkg>.

=head2 get_registry()

    my $registry = Contract::Declare::Interface::get_registry();

Returns the process-wide interface registry as a hashref of the shape:

    {
        $interface_name => {
            $sub_name => {
                PKG     => $declaring_package,
                FILE    => $declaring_file,
                LINE    => $declaring_line,
                EXPECTS => [ $type_name, ... ],
                RETURNS => [ $type_name, ... ],
            },
            ...
        },
        ...
    }

This is an internal function, primarily useful for introspection and
testing; L<Contract::Declare::Implements> is the intended consumer.

=head1 SEE ALSO

L<Contract::Declare>, L<Contract::Declare::Implements>, L<Types::Standard>

=cut