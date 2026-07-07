use v5.32;
use warnings;
use Test2::V0;
use FindBin;
use Capture::Tiny qw/capture/;

# These scenarios all panic while *compiling* the offending package
# (via a BEGIN-time attribute handler, or an INIT-time wrapping pass).
# That kind of failure can't be caught with eval{}/dies{} in-process
# without also destroying the rest of this test file's own compile
# unit, so each case is run in its own perl subprocess.

my $lib     = "$FindBin::Bin/../lib";
my $test_lib = "$FindBin::Bin/lib";

sub run_fixture {
    my ($code) = @_;
    my ($stdout, $stderr, $exit) = capture {
        system($^X, '-I', $lib, '-I', $test_lib, '-e', $code);
    };
    return ($exit >> 8, $stderr);
}

subtest 'declaring two interfaces under the same name panics' => sub {
    my ($status, $stderr) = run_fixture(
        'use TestIface::DuplicateA; use TestIface::DuplicateB;'
    );
    isnt($status, 0, 'process exits non-zero');
    like($stderr, qr/panic: interface `DupIface` already defined/, 'panic message names the clashing interface');
};

subtest 'applying :Expects twice to the same sub panics' => sub {
    my ($status, $stderr) = run_fixture('use TestIface::DuplicateAttr;');
    isnt($status, 0, 'process exits non-zero');
    like(
        $stderr,
        qr/panic: already defined sub `foo` for interface `DuplicateAttrIface`/,
        'panic message names the sub and interface',
    );
};

subtest ':Expects/:Returns outside a declared interface panics' => sub {
    my ($status, $stderr) = run_fixture(
        'require Contract::Declare::Interface; require TestIface::NoImport;'
    );
    isnt($status, 0, 'process exits non-zero');
    like(
        $stderr,
        qr/panic: can't find any interface implemented in TestIface::NoImport/,
        'panic message names the offending package',
    );
};

subtest 'implementing an unregistered interface panics at use-time' => sub {
    my ($status, $stderr) = run_fixture('use TestImpl::UsesUnknownIface;');
    isnt($status, 0, 'process exits non-zero');
    like(
        $stderr,
        qr/panic: can't find interface `ThisIfaceDoesNotExist`/,
        'panic message names the unknown interface',
    );
};

subtest 'missing a required method panics at INIT-time' => sub {
    my ($status, $stderr) = run_fixture('use TestImpl::IncompleteCalculator;');
    isnt($status, 0, 'process exits non-zero');
    like(
        $stderr,
        qr/TestImpl::IncompleteCalculator donesn't implement interface `Calculator`: can't do the `greet` sub/,
        'panic message names the missing sub',
    );
};

subtest 'a fully-implemented class loads cleanly' => sub {
    my ($status, $stderr) = run_fixture(
        'use TestImpl::GoodCalculator; print "loaded ok: ", TestImpl::GoodCalculator->new->add(1, 2), "\n";'
    );
    is($status, 0, 'process exits zero') or diag $stderr;
};

done_testing;
