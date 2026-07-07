use v5.14;
use warnings;

# Implements TestIface::Calculator correctly in shape, but its `add`
# returns a value that fails the interface's :Returns(Int) contract.
# Used to exercise return-value validation.
package TestImpl::BadReturnCalculator {
    use TestIface::Calculator;
    use Contract::Declare::Implements qw/Calculator/;

    sub new { return bless {}, shift }

    sub add {
        my ($self, $a, $b) = @_;
        return "not-a-number";
    }

    sub greet {
        my ($self, $name) = @_;
        return "Hello, $name!";
    }
}

1;
