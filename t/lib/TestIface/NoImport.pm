use v5.14;
use warnings;

# Uses the :Expects attribute without ever calling
# `use Contract::Declare::Interface`. Since :Expects/:Returns are
# installed globally into UNIVERSAL as soon as Contract::Declare::Interface
# has been loaded by anyone, this compiles far enough to reach the
# attribute handler, which then fails to find an interface for this
# package. Only ever loaded from a subprocess (after Interface.pm has
# been `require`d, so the attribute handler exists).
package TestIface::NoImport {
    sub foo :Expects(Str) :Returns(Str) { return $_[0] }
}

1;
