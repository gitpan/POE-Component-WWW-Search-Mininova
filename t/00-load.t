#!perl

use strict;
use warnings;
use Test::More tests => 9;

BEGIN {
    use_ok('Carp');
    use_ok('POE');
    use_ok('POE::Wheel::Run');
    use_ok('POE::Filter::Line');
    use_ok('POE::Filter::Reference');
    use_ok('WWW::Search::Mininova');

	use_ok( 'POE::Component::WWW::Search::Mininova' );
}

diag( "Testing POE::Component::WWW::Search::Mininova $POE::Component::WWW::Search::Mininova::VERSION, Perl $], $^X" );

use POE qw(Component::WWW::Search::Mininova);
my $poco = POE::Component::WWW::Search::Mininova->spawn(debug=>1);
isa_ok($poco,'POE::Component::WWW::Search::Mininova');
can_ok($poco, qw(spawn shutdown session_id search));


POE::Session->create(
    inline_states => {
        _start => sub { $poco->shutdown },
    },
);

$poe_kernel->run;