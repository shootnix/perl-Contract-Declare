use v5.14;
use warnings;

# Interface used by most of the runtime/registry tests: two methods,
# a couple of scalar arguments each, to keep validate() straightforward
# to reason about.
package TestIface::Calculator {
    use Contract::Declare::Interface name => 'Calculator';

    sub add   :Expects(Object, Int, Int) :Returns(Int);
    sub greet :Expects(Object, Str)      :Returns(Str);
}

1;
