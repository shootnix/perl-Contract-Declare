use v5.14;

use strict;
use warnings;


use App::Adaptor::Repo;
use App::Impl::Repo::Memory;




my $mrepo = App::Impl::Repo::Memory->new();
my $repo = App::Adaptor::Repo->new($mrepo);


$repo->set({ id => 1, value => 'one' });
$repo->set({ id => 2, value => 'two' });

my ($o, $err) = $repo->get(1);
if ($err) {
    warn $err;
    exit;
}
warn $o->{value};


use App::Adaptor::Interfaces;
use App::Impl::Greeter;
use App::Impl::User;


my $gi = App::Impl::Greeter->new();

my $ui = App::Impl::User->new();

my $greeter = App::Interface::Greeter->new($gi);

say $greeter->greet("Bill");


my $user = App::Interface::User->new($ui);

say $user->get_name;