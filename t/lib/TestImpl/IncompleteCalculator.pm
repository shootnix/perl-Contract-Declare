use v5.32;
use warnings;

# Declares itself an implementor of Calculator but only defines `add`,
# not `greet`. Should panic during Implements.pm's INIT-time wrapping
# pass. Only ever loaded from a subprocess.
package TestImpl::IncompleteCalculator {
    use TestIface::Calculator;
    use Contract::Declare::Implements qw/Calculator/;

    sub new { return bless {}, shift }

    sub add {
        my ($self, $a, $b) = @_;
        return $a + $b;
    }
}

1;
