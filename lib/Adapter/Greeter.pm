use Contract::Declare2;

use Types::Standard qw/Str/;


interface Greeter::SAY {
    sub sayHello :Args(Str) :Returns();
};


1;