package Reader {
    use Contract::Declare::Interface;

    sub read :Expects(Str, Int) :Returns(HashRef);
}

#package JSONReader {
#    use Contract::Declare::Implements qw/Reader/;
#
#    use JSON::XS qw/decode_json/;
#
#    sub read {
#        my ($filename) = @_;
#
#        ...
#    }
#}

sub main {
    #my $r = JSONReader->new();
}