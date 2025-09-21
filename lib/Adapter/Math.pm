use Contract::Declare2;

use Types::Standard qw/Int/;


interface Math::Add {
    sub add :Args(Int, Int) :Returns(Int);
}

1;