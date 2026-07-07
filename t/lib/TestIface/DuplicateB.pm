use v5.32;
use warnings;

# See TestIface::DuplicateA.
package TestIface::DuplicateB {
    use Contract::Declare::Interface name => 'DupIface';

    sub bar :Expects(Any) :Returns(Any);
}

1;
