#use Contract::Declare2;

#use Types::Standard qw/Str Any/;


#interface Greeter::SAY {
#    sub sayHello :Args(Str) :Returns();
#};


package Greeter::SAY {
    use Contract::Declare2 ':interface';

    sub sayHello :Args(Str) :Returns();
}


1;