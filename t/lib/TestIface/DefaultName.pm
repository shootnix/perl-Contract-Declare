use v5.14;
use warnings;

# Declares an interface with no explicit `name`, to verify it defaults
# to the declaring package's own name.
package TestIface::DefaultName {
    use Contract::Declare::Interface;

    sub ping :Expects(Object) :Returns(Bool);
}

1;
