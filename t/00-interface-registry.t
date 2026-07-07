use v5.14;
use warnings;
use Test2::V0;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";

use TestIface::Calculator;
use TestIface::DefaultName;

my $registry = Contract::Declare::Interface::get_registry();

subtest 'named interface is registered under its explicit name' => sub {
    ok(exists $registry->{Calculator}, 'Calculator interface exists in the registry');
    is(
        [ sort keys %{ $registry->{Calculator} } ],
        [qw/add greet/],
        'registry lists exactly the subs declared on the interface',
    );
};

subtest 'unnamed interface defaults to the declaring package name' => sub {
    ok(exists $registry->{'TestIface::DefaultName'}, 'interface registered under the package name');
    ok(!exists $registry->{Calculator}{ping}, 'sanity: ping did not leak into an unrelated interface');
};

subtest 'EXPECTS/RETURNS metadata is captured verbatim' => sub {
    my $add = $registry->{Calculator}{add};
    is($add->{EXPECTS}, [qw/Object Int Int/], 'add EXPECTS captured in declaration order');
    is($add->{RETURNS}, [qw/Int/],            'add RETURNS captured');

    my $greet = $registry->{Calculator}{greet};
    is($greet->{EXPECTS}, [qw/Object Str/], 'greet EXPECTS captured');
    is($greet->{RETURNS}, [qw/Str/],        'greet RETURNS captured');
};

subtest 'declaration site is recorded' => sub {
    my $add = $registry->{Calculator}{add};
    is($add->{PKG}, 'TestIface::Calculator', 'PKG points at the declaring package');
    like($add->{FILE}, qr/Calculator\.pm$/, 'FILE points at the declaring file');
    ok($add->{LINE} > 0, 'LINE is a positive line number');
};

subtest 're-registering an interface name is rejected' => sub {
    # `use` always runs at compile time, so to exercise import() as a
    # genuine runtime failure (catchable by dies {}) we call it directly
    # instead of writing a nested `use` statement.
    my $e = dies {
        Contract::Declare::Interface->import(name => 'Calculator');
    };
    like($e, qr/panic: interface `Calculator` already defined/, 'duplicate interface name panics');
};

done_testing;
