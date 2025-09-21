package App::Impl::Greeter;

use Role::Tiny::With;
with 'App::Interface::Greeter';

sub new { bless {}, shift }


sub greet {
    my ($self, $name) = @_;

    return "Hello, $name!";
}

1;