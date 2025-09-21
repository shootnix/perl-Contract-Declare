package Impl::Greeter;

use v5.32;


sub sayHello {
    my ($this, $name) = @_;

    say "Hello, $name";
}

1;