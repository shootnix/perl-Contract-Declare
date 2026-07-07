use v5.32;
use warnings;
use Test2::V0;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";

# Documents a real caveat (see Contract::Declare::Implements/"HOW AND WHEN
# METHODS ARE WRAPPED"): contract enforcement is wired up in an INIT
# block, which only runs once, right after the whole program finishes
# compiling. A class that is `require`d at runtime *after* that point
# compiles too late to be wrapped, so its methods run completely
# unchecked - no exception, no warning, just silent pass-through.
#
# TestImpl::GoodCalculator is deliberately *not* `use`d anywhere above,
# so this file's own INIT phase runs without ever having seen it.

require TestImpl::GoodCalculator;

my $calc = TestImpl::GoodCalculator->new;

subtest 'a lazily-required implementor is never wrapped' => sub {
    my $extra_args = $calc->add(1, 2, 3);
    is(
        $extra_args, 3,
        'wrong arity is silently accepted (a wrapped call would panic here)',
    );

    my $wrong_type = $calc->add('not-an-int', 2);
    is(
        $wrong_type, 2,
        'a bad argument type is silently accepted too (Perl just numifies "not-an-int" to 0)',
    );
};

done_testing;
