package App::Impl::User;

use Role::Tiny::With;
with 'App::Interface::User', 'App::Interface::Greeter';


sub new { bless {}, shift }

sub get_name { "Bill" }
sub get_email { 'bill@gmail.com' }

sub greet {
    my ($self, $name) = @_;

    return "Hey, $name!";
}

1;