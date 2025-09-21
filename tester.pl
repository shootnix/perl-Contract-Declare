use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/lib";


use Adapter::Greeter;
use Adapter::Math;
use Impl::Greeter;

use Class::MOP ();


#$my $greeter_impl = Impl::Greeter->new();
my $greet = Greeter::SAY->new('Impl::Greeter');

$greet->sayHello('Alexander');

#my $add = Math::Add->new();

#my $wtf = Class::MOP::Class->initialize('Math::Add');
#use Data::Dumper;

#warn Data::Dumper::Dumper $wtf;

#use Contract::Declare2;

#interface Greeter {             
#    sub sayHello;
#};

