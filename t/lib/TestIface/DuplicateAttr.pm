use v5.32;
use warnings;

# Applies :Expects twice to the same sub, which should panic as soon as
# this file compiles. Only ever loaded from a subprocess.
package TestIface::DuplicateAttr {
    use Contract::Declare::Interface name => 'DuplicateAttrIface';

    sub foo :Expects(Str) :Expects(Int) :Returns(Str);
}

1;
