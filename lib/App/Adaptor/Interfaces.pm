package App::Adaptor::Interfaces;

use v5.14;

use Contract::Declare;
use Types::Standard qw/Str/;


contract 'App::Interface::Greeter' => interface {
    method 'greet' => (Str), returns(Str);
};

contract 'App::Interface::User' => interface {
    method 'get_name'  => (), returns(Str);
    method 'get_email' => (), returns(Str);
};


1;