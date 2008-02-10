#!perl

use strict;
use warnings;

die "Usage: perl mini.pl <search_term>\n"
    unless @ARGV;

use lib '../lib';
use POE qw(Component::WWW::Search::Mininova);

my $Term_to_search = shift;

my $poco = POE::Component::WWW::Search::Mininova->spawn;

POE::Session->create(
    package_states => [
        main => [qw(_start mini)],
    ],
);

$poe_kernel->run;

sub _start {
    $poco->search({ event => 'mini', term => $Term_to_search });
}

sub mini {
    my $results = $_[ARG0];

    if ( $results->{error} ) {
        print "Error: $results->{error}\n";
    }
    else {
        if ( defined $results->{out}{did_you_mean} ) {
            print "Did you mean to search for "
                    . "$results->{out}{did_you_mean}?\n";
        }
        
        print "Found $results->{out}{results_found} results\n";
        foreach my $result ( @{ $results->{out}{results} } ) {
            print "\n";
            if ( $result->{is_private} ) {
                print "Private tracker\n";
            }
            print <<"END_RESULT_DATA";
            Torrent name: $result->{name}
            Number of seeds: $result->{seeds}
            Number of leechers: $result->{leechers}
            Torrent page: $result->{uri}
            Download URI: $result->{download_uri}
            Torrent size: $result->{size}
            Category: $result->{category}
            Sub category: $result->{subcategory}
            Was added on: $result->{added_date}

END_RESULT_DATA
        }
    }
    $poco->shutdown;
}


