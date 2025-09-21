
use Types::Standard qw/Int Maybe/;

package Math::Add {
    use Contract::Declare2 ':interface';

    sub add :Args(Int, Int) :Returns(Int);
};

package Math::Div {
    use Contract::Declare2 ':interface';

    sub nonzero { $_[0] == 0 ? 0 : 1 }

    sub div :Args(Int, Maybe[Int]) :Returns(Int)
}

1;