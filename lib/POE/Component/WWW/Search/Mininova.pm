package POE::Component::WWW::Search::Mininova;

use 5.008008;
use strict;
use warnings;
our $VERSION = '0.03';

use WWW::Search::Mininova;

use POE 0.38 qw(Wheel::Run  Filter::Line  Filter::Reference);
use Carp;


sub spawn {
    my $class = shift;
    croak "$class requires an even number of arguments"
        if @_ & 1;  

    my %args = @_;
    $args{ lc $_ } = delete $args{ $_ } for keys %args;

    delete $args{options}
        unless ref $args{options} eq 'HASH';

    eval {
        require WWW::Search::Mininova;
    };
    croak "Failed to load WWW::Search::Mininova ($@)"
        if $@;

    my $self = bless \%args, $class;

    $self->{session_id} = POE::Session->create(
        object_states => [
            $self => {
                search   => '_search',
                shutdown => '_shutdown',
            },
            $self => [
                qw(
                    _child_error
                    _child_closed
                    _child_stdout
                    _child_stderr
                    _sig_child
                    _start
                )
            ],
        ], (
            defined $args{options}
                ? ( options => $args{options} )
                : ()
        )
    )->ID;

    return $self;
}

sub _start {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    $self->{session_id} = $_[SESSION]->ID();
    
    if ( $self->{alias} ) {
        $kernel->alias_set( $self->{alias} );
    }
    else {
        $kernel->refcount_increment(
            $self->{session_id} => __PACKAGE__
        );
    }

    $self->{wheel} = POE::Wheel::Run->new(
        Program => \&_search_wheel,
        ErrorEvent => '_child_error',
        CloseEvent  => '_child_closed',
        StdoutEvent => '_child_stdout',
        StderrEvent => '_child_stderr',
        StdioFilter => POE::Filter::Reference->new(),
        StderrFilter => POE::Filter::Line->new(),
        ( $^O eq 'MSWin32' ? ( CloseOnCall => 0 ) : ( CloseOnCall => 1 ) )
    );

    $kernel->yield('shutdown')
        unless $self->{wheel};

    $kernel->sig_child( $self->{wheel}->PID, '_sig_child' );

    undef;
}

sub _sig_child {
    $poe_kernel->sig_handled();
}

sub session_id {
    return $_[0]->{session_id};
}

sub search {
    my $self = shift;
    $poe_kernel->post( $self->{session_id} => 'search' => @_ );
}

sub _search {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    my $sender = $_[SENDER]->ID;
    
    return
        if $self->{shutdown};

    my $args;
    if ( ref $_[ARG0] eq 'HASH' ) {
        $args = { %{ $_[ARG0] } };
    }
    else {
        warn "Arguments must be passed in a hashref... trying to adjust";
        $args = { @_[ ARG0..$#_ ] };
    }

    $args->{ lc $_ } = delete $args->{ $_ }
        for grep { $_ !~ /^_/ } keys %{ $args };

    unless ( $args->{event} ) {
        warn "No event to send output to was specified";
        return;
    }

    unless ( $args->{term} ) {
        warn "No search term specified";
        return;
    }

    if ( $args->{session} ) {
        if ( my $session_ref = $kernel->alias_resolve( $args->{session} ) ) {
            $args->{sender} = $session_ref->ID;
        }
        else {
            warn "Could not resolve ``session`` to a valid POE session";
            return;
        }
    }
    else {
        $args->{sender} = $sender;
    }
    
    $kernel->refcount_increment( $args->{sender} => __PACKAGE__ );
    
    $self->{wheel}->put( $args );
}

sub shutdown {
    my $self = shift;
    $poe_kernel->call( $self->{session_id} => 'shutdown' => @_ );
}

sub _shutdown {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    $kernel->alarm_remove_all();
    $kernel->alias_remove( $_ ) for $kernel->alias_list;

    $kernel->refcount_decrement( $self->{session_id} => __PACKAGE__ )
        unless $self->{alias};

    $self->{shutdown} = 1;
    $self->{wheel}->shutdown_stdin
        if $self->{wheel};

    undef;
}

sub _child_closed {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    warn "Child closed @_[ARG0..$#_]\n"
        if $self->{debug};

    delete $self->{wheel};
    $kernel->yield('shutdown')
        unless $self->{shutdown};

    undef;
}

sub _child_error {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    warn "Child error: @_[ARG0..$#_]\n"
        if $self->{debug};

    delete $self->{wheel};
    $kernel->yield('shutdown')
        unless $self->{shutdown};

    undef;
}

sub _child_stderr {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    warn "Child stderr: @_[ARG0..$#_]\n"
        if $self->{debug};

    undef;
}

sub _child_stdout {
    my ( $kernel, $self, $input ) = @_[ KERNEL, OBJECT, ARG0 ];
    
    my $session = delete $input->{sender};
    my $event   = delete $input->{event};

    $kernel->post( $session => $event => $input );
    $kernel->refcount_decrement( $session => __PACKAGE__ );
    
    undef;
}

sub _search_wheel {

    if ( $^O eq 'MSWin32' ) {
        binmode STDIN;
        binmode STDOUT;
    }

    my $raw;
    my $size = 4096;
    my $filter = POE::Filter::Reference->new;

    my $mini = WWW::Search::Mininova->new;

    while ( sysread ( STDIN, $raw, $size ) ) {
        my $requests = $filter->get( [ $raw ] );
        foreach my $req ( @{ $requests } ) {
            foreach my $arg ( qw( category sort timeout ua debug ) ) {
                if ( $req->{ $arg } ) {
                    $mini->$arg( $req->{ $arg } );
                }
            }
            $req->{out} = $mini->search( $req->{term} )
                or $req->{error} = $mini->error;

            my $response = $filter->put( [ $req ] );
            print STDOUT @$response;
        }
    }
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

POE::Component::WWW::Search::Mininova - non-blocking POE wrapper for
WWW::Search::Mininova

=head1 SYNOPSIS

    use strict;
    use warnings;
    
    use POE qw(Component::WWW::Search::Mininova);
    
    my $mini_poco
        = POE::Component::WWW::Search::Mininova->spawn( alias => 'mini' );
    
    POE::Session->create(
        package_states => [
            'main' => [ qw(_start mini) ],
        ]
    );
    
    $poe_kernel->run;
    
    sub _start { 
        my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
        
        $mini->search( {
                term             => 'test',
                category         => 'Music',
                sort             => 'Seeds',
                ua               => 'Torrent Searcher',
                timeout          => 180,
    
                event            => 'mini',
                _arbitrary_value => 'whatever',
        } );
        
        $kernel->post(
        'mini' => 'search' => {
                term             => 'test',
    
                event            => 'mini',
                _arbitrary_value => 'whatever',
            }
        );
        undef;
    }
    
    sub mini {
        my ( $kernel, $results ) = @_[ KERNEL, ARG0 ];

        if ( $results->{error} ) {
            print "ZOMG! An error: $results->{error}\n";
        }
        else {
            use Data::Dumper;
            print Dumper( $results->{out} );
        }
    
        print $results->{_arbitrary_value}, "\n";
    
        $kernel->post( 'mini' => 'shutdown' );
    
        undef;
    }


=head1 DESCRIPTION

The module is a simple non-blocking L<POE> wrapper for
 L<WWW::Search::Mininova>

=head1 CONSTRUCTOR

    my $mini = POE::Component::WWW::Search::Mininova->spawn;

Takes a three I<optional> arguments.

=head2 alias

    POE::Component::WWW::Search::Mininova->spawn( alias => 'mini' );

Specifies a POE Kernel alias for the component.

=head2 options

    POE::Component::WWW::Search::Mininova->spawn(
        options => {
            trace => 1,
            default => 1,
        },
    );

A hashref of POE Session options to pass to the component's session.

=head2 debug

    POE::Component::WWW::Search::Mininova->spawn( debug => 1 );

Turns on printing of a few debug messages.
I<Note:> you must set this option to a true value if you wish to print out
debug messages from L<WWW::Search::Mininova> object.

=head1 METHODS

These are the object-oriented methods of the components.

=head2 search

    $mini_poco->search(
        {
            term => 'foos',
            event => 'mini',
        }
    );

Takes hashref of arguments. See C<search> method below for description.

=head2 session_id

    my $mini_id = $mini_poco->session_id;

Takes no arguments. Returns POE Session ID of the component.

=head2 shutdown

    $mini_poco->shutdown;

Takes no arguments. Terminates the component.

=head1 ACCEPTED EVENTS

=head2 search

    $poe_kernel->post( 'mini' => 'search' => {
            term  => 'foos',
            event => 'mini',
        }
    );
    
    $poe_kernel->post( 'mini' => 'search' => {
            term             => 'foos',
            event            => 'mini',
            timeout          => 10,
            _arbitrary_value => 'whatever',
            _moar_shtuf      => 'something else',
        }
    );

Instructs the component to make a search. Requires a hashref as an argument.
Hashref keys are as follows:

=head3 term

    { term => 'foos' }

B<Mandatory>. The term to search mininova.org for. The value you would pass as an argument
to the C<search()> method of L<WWW::Search::Minonova> object.

=head3 event

    { event => 'mini' }

B<Mandatory>. The event name to send the response to.

=head3 category

    { category => 'Music' }

B<Optional>. Tells the component on which category to perform the search on.
See L<WWW::Search::Minonova> object's C<category> method for more information.

=head3 sort

    { sort => 'Seeds' }

B<Optional>. Tells the component on which column the most relevant results
should be based on. See L<WWW::Search::Minonova> object's C<sort()> method
for more information.

=head3 timeout

    { timeout => 50 }

B<Optional>. Search request timeout. See L<WWW::Search::Minonova> object's
C<timeout()> method for details.

=head3 ua

    { ua => 'Torrent Searcher' }

B<Optional>. User-Agent string to use for searches. L<WWW::Search::Minonova> object's C<ua()> method for details.

=head3 debug

    { debug => 1 }

B<Optional>. Turn on debuggin messages from L<WWW::Search::Minonova> object. See L<WWW::Search::Minonova> object's C<debug()> method for details.
B<Note:> the C<debug> argument to the component's contstructor must also be
set to a true value in order for this option to work.

=head3 session

    { session => $some_other_session_ref }
    
    { session => 'printer' }
    
    { session => $session->ID }

B<Optional>. An alternative session alias, reference or ID that the
response should be sent to, defaults to sending session.

=head3 user defined values

    {
        _something       => 'foo',
        _something_else  => \@bars,
    }

B<Optional>. Any argument starting with a C<_> (underscore) character will
not affect the component but will be passed intact along with the search
results when the search is completed. See OUTPUT section below for details.

=head2 shutdown

    $poe_kernel->post( 'mini' => 'shutdown' );

Takes no arguments. Shuts down the component.

=head1 OUTPUT

Whether the OO or POE API is used the component passes responses back via a POE event. C<ARG0> will be a hashref with the following key/value pairs:

    sub mini {
        my ( $kernel, $results ) = @_[ KERNEL, ARG0 ];
        
        if ( $results->{error} ) {
            print "ZOMG! An error: $results->{error}\n";
        }
        else {
            use Data::Dumper;
            print Dumper( $results->{out} );
        }
    
        print $results->{_arbitrary_value}, "\n";
    
        $kernel->post( 'mini' => 'shutdown' );
    
        undef;
    }

=head2 out

Search results. If an error occured it will be C<undef> and C<error> key will
be set explaining the reason. The format of the value is the same as the 
return value of L<WWW::Search::Minonova> object's C<search> method. See
L<WWW::Search::Minonova> object's C<search> method for detailed explanation.

=head2 error

If an error occured during the search this key will be present and will
contain the error message.

=head2 user defined values

All of the arguments starting with C<_> (underscore) character will also be
present in the return with their values intact.

=head1 SEE ALSO

L<POE> L<WWW::Search::Mininova>

=head1 AUTHOR

Zoffix Znet, E<lt>zoffix@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Zoffix Znet

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
