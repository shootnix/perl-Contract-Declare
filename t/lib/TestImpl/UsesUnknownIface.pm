use v5.32;
use warnings;

# Declares itself an implementor of an interface that was never
# registered. Should panic at `use` time, inside Implements::import.
# Only ever loaded from a subprocess.
package TestImpl::UsesUnknownIface {
    use Contract::Declare::Implements qw/ThisIfaceDoesNotExist/;
}

1;
