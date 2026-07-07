use v5.14;
use warnings;
use Test2::V0;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";

use TestImpl::GoodCalculator;
use TestImpl::BadReturnCalculator;

my $calc = TestImpl::GoodCalculator->new;

subtest 'a valid call returns the real result' => sub {
    is($calc->add(2, 3), 5, 'add(2, 3) returns 5, not the validator return value');
    is($calc->greet('World'), 'Hello, World!', 'greet() returns the real string');
};

subtest 'return value respects calling context' => sub {
    my @list = $calc->greet('List');
    is(\@list, ['Hello, List!'], 'list context yields a one-element list');

    my $scalar = $calc->greet('Scalar');
    is($scalar, 'Hello, Scalar!', 'scalar context yields the value directly');
};

subtest 'wrong number of arguments panics' => sub {
    my $e = dies { $calc->add(1) };
    like(
        $e,
        qr/panic: number of expecting parameters doesn't match for TestImpl::GoodCalculator::add\(\)/,
        'missing argument is rejected before the real method runs',
    );

    $e = dies { $calc->add(1, 2, 3) };
    like(
        $e,
        qr/panic: number of expecting parameters doesn't match/,
        'extra argument is rejected too',
    );
};

subtest 'argument type mismatch panics' => sub {
    my $e = dies { $calc->add('not-an-int', 2) };
    like($e, qr/panic: types mismatch: Int/, 'non-Int argument is rejected');

    $e = dies { $calc->greet([]) };
    like($e, qr/panic: types mismatch: Str/, 'non-Str argument is rejected');
};

subtest 'calling on a bare invocant still validates the invocant type' => sub {
    my $e = dies { TestImpl::GoodCalculator::add(undef, 1, 2) };
    like($e, qr/panic: types mismatch: Object/, 'undef invocant fails the Object check');
};

subtest 'return type mismatch panics' => sub {
    my $bad = TestImpl::BadReturnCalculator->new;
    my $e = dies { $bad->add(1, 2) };
    like($e, qr/panic: types mismatch: Int/, 'a non-Int return value is rejected');

    # the well-behaved method on the same object is unaffected
    is($bad->greet('Ok'), 'Hello, Ok!', 'other methods on the same class are wrapped independently');
};

subtest 'each call is validated independently (no state leaks between calls)' => sub {
    ok(dies { $calc->add('bad', 2) }, 'first call fails as expected');
    is($calc->add(4, 5), 9, 'a subsequent valid call still succeeds');
};

done_testing;
