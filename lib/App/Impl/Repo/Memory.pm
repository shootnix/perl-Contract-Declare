package App::Impl::Repo::Memory;

use Role::Tiny::With;
with 'App::Adaptor::Repo';

sub new { bless { objects => {} }, shift }

sub get {
    my ($self, $id) = @_;

    if (!exists $self->{objects}->{$id}) {
        return (undef, "not found");
    }

    return ($self->{objects}->{$id}, undef);
}

sub set {
    my ($self, $obj) = @_;

    $self->{objects}->{$obj->{id}} = $obj;

    return undef;
}

1;