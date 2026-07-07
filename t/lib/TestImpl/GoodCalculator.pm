use v5.32;
use warnings;

# A well-behaved implementor of TestIface::Calculator: correct method
# names, correct arity, correct return types.
package TestImpl::GoodCalculator {
    use TestIface::Calculator;
    use Contract::Declare::Implements qw/Calculator/;

    sub new { return bless {}, shift }

    sub add {
        my ($self, $a, $b) = @_;
        return $a + $b;
    }

    sub greet {
        my ($self, $name) = @_;
        return "Hello, $name!";
    }
}

1;
