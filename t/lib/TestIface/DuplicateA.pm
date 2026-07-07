use v5.14;
use warnings;

# Paired with TestIface::DuplicateB: both register the same interface
# name, to exercise the "interface already defined" panic. Only ever
# loaded from a subprocess, since the second `use` is fatal.
package TestIface::DuplicateA {
    use Contract::Declare::Interface name => 'DupIface';

    sub foo :Expects(Any) :Returns(Any);
}

1;
