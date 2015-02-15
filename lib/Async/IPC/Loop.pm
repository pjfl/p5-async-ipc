package Async::IPC::Loop;

use strictures;
use feature 'state';

use AnyEvent;
use Async::Interrupt;
use Class::Usul::Functions qw( arg_list );
use English                qw( -no_match_vars );
use Scalar::Util           qw( blessed );

my $Cache = {};

# Private methods
my $_events = sub {
   return $Cache->{ $PID }->{ $_[ 1 ] } ||= {};
};

my $_sigattaches = sub {
   return $Cache->{ $PID }->{_sigattaches} ||= {};
};

# Construction
sub new {
   my $self = shift; return bless arg_list( @_ ), blessed $self || $self;
}

# Public methods
sub once {
   my ($self, $tmout, $cb) = @_;

   defined $tmout and my $w = AnyEvent->timer( after => $tmout, cb => $cb );
   AnyEvent->_poll; # Undocumented method
   return;
}

sub start {
   my $self = shift; (local $self->{cv} = AnyEvent->condvar)->recv; return;
}

sub start_nb {
   my ($self, $cb) = @_;

   (local $self->{cv} = AnyEvent->condvar)->cb( sub {
      my @res = $_[ 0 ]->recv; defined $cb and $cb->( @res ) } );

   return;
}

sub stop {
   shift->{cv}->send( @_ ); return;
}

sub watch_child {
   my ($self, $id, $cb) = @_; my $w = $self->$_events( 'watchers' );

   if ($id) {
      my $cv = $w->{ $id }->[ 0 ] = AnyEvent->condvar;

      $w->{ $id }->[ 1 ] = AnyEvent->child( pid => $id, cb => sub {
         defined $cb and $cb->( @_ ); $cv->send } );
   }
   else {
      for (sort { $a <=> $b } $cb ? $cb->() : keys %{ $w }) {
         $w->{ $_ } and $w->{ $_ }->[ 0 ] and $w->{ $_ }->[ 0 ]->recv;
         $self->unwatch_child( $_ );
      }
   }

   return;
}

sub unwatch_child {
   my $w = $_[ 0 ]->$_events( 'watchers' ); my $id = $_[ 1 ];

   undef $w->{ $id }->[ 0 ]; undef $w->{ $id }->[ 1 ]; delete $w->{ $id };
   return;
}

sub watch_idle {
   my ($self, $id, $cb) = @_; my $w = $self->$_events( 'idle' );

   $w->{ $id } = AnyEvent->idle( cb => sub {
      delete $w->{ $id }; $cb->( @_ ) } );
   return;
}

sub unwatch_idle {
   delete $_[ 0 ]->$_events( 'idle' )->{ $_[ 1 ] }; return;
}

sub watch_read_handle {
   my ($self, $fh, $cb) = @_; my $h = $self->$_events( 'handles' );

   $h->{ "r${fh}" } = AnyEvent->io( cb => $cb, fh => $fh, poll => 'r' );
   return;
}

sub unwatch_read_handle {
   delete $_[ 0 ]->$_events( 'handles' )->{ 'r'.$_[ 1 ] }; return;
}

sub watch_signal {
   my ($self, $signal, $cb) = @_; my $attaches;

   unless ($attaches = $self->$_sigattaches->{ $signal }) {
      my $s = $self->$_events( 'signals' ); my @attaches;

      $s->{ $signal } = AnyEvent->signal( signal => $signal, cb => sub {
         for my $attachment (@attaches) { $attachment->() }
      } );

      $attaches = $self->$_sigattaches->{ $signal } = \@attaches;
   }

   push @{ $attaches }, $cb; return \$attaches->[ -1 ];
}

sub unwatch_signal {
   my ($self, $signal, $id) = @_;

   # Can't use grep because we have to preserve the addresses
   my $attaches = $self->$_sigattaches->{ $signal } or return;

   for (my $i = 0; $i < @{ $attaches }; ) {
      not $id and splice @{ $attaches }, $i, 1, () and next;
      $id == \$attaches->[ $i ] and splice @{ $attaches }, $i, 1, () and last;
      $i++;
   }

   scalar @{ $attaches } and return;
   delete $self->$_sigattaches->{ $signal };
   delete $self->$_events( 'signals' )->{ $signal };
   return;
}

sub watch_time {
   my ($self, $id, $cb, $after, $interval) = @_;

   defined $interval and $interval eq 'abs' and $after -= time;
   defined $interval and $interval =~ m{ \A (?: abs | rel ) \z }mx
       and $interval = 0;

   $after > 0 or $after = 0; my @args = (after => $after, cb => $cb);

   not defined $interval and push @args, 'interval', $after;
       defined $interval and $interval and push @args, 'interval', $interval;

   my $t = $self->$_events( 'timers' ); $t->{ $id }->[ 0 ] = $cb;

   $t->{ $id }->[ 1 ] = AnyEvent->timer( @args );
   return;
}

sub unwatch_time {
   my $t = $_[ 0 ]->$_events( 'timers' ); my $id = $_[ 1 ];

   exists $t->{ $id } or return 0; my $cb = $t->{ $id }->[ 0 ];

   undef $t->{ $id }->[ 0 ]; undef $t->{ $id }->[ 1 ]; delete $t->{ $id };

   return $cb;
}

sub watch_write_handle {
   my ($self, $fh, $cb) = @_; my $h = $self->$_events( 'handles' );

   $h->{ "w${fh}" } = AnyEvent->io( cb => $cb, fh => $fh, poll => 'w' );
   return;
}

sub unwatch_write_handle {
   delete $_[ 0 ]->$_events( 'handles' )->{ 'w'.$_[ 1 ] }; return;
}

sub uuid {
   state $uuid //= 1; return $uuid++;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Loop - Callback style API for AnyEvent

=head1 Synopsis

   use Async::IPC::Loop;

   my $loop = Async::IPC::Loop->new;

   # Call the subroutine when the child process exits
   $loop->watch_child( $process_id, sub { ... } );

   # Set a handler to watch for the terminate signal
   $loop->watch_signal( TERM => sub { $loop->stop } );

   # Enter into the event loop. Wait for the event loop to terminate
   $loop->start;

   # Wait for all child processes to exit
   $loop->watch_child( 0 );

=head1 Description

Uses L<AnyEvent> and L<EV> to implement a callback style asyncronous API

=head1 Configuration and Environment

Defines no attributes

=head1 Subroutines/Methods

=head2 C<new>

   $loop = Async::IPC::Loop->new;

Constructor

=head2 C<once>

   $loop->once( $timeout, $callback_sub );

Process events once and then return. The optional time out and callback
subroutine is used to terminate the waiting for events after a given time

=head2 C<start>

   $loop->start;

Enter into the event loop. Wait here, processing events until the event loop
is terminated

=head2 C<start_nb>

   $loop->start_nb;

Same a L</start> but returns immediately

=head2 C<stop>

   $loop->stop;

Terminate the event loop. When this is called the L</start> method returns

=head2 C<watch_child>

   $loop->watch_child( $process_id, $callback_sub );

If the process id is greater than zero, the callback subroutine is invoked
when the process exits.

If the process id is zero and there is no callback subroutine, wait for all
child processes to exit. If the callback subroutine is supplied then, when
called, it should return the list of process ids to wait for

=head2 C<unwatch_child>

   $loop->unwatch_child( $process_id );

Delete the child watcher for the specified process

=head2 C<watch_idle>

   $loop->watch_idle( $id, $callback_sub );

Executes the callback after any pending events have been processed

=head2 C<unwatch_idle>

   $loop->unwatch_idle( $id );

Delete the idle watcher for the specified id

=head2 C<watch_read_handle>

   $loop->watch_read_handle( $file_handle, $callback_sub );

The callback subroutine is invoked when the file handle becomes readable

=head2 C<unwatch_read_handle>

   $loop->unwatch_read_handle( $file_handle );

Delete the file handle watcher for the specified file handle

=head2 C<watch_signal>

   $attach_id = $loop->watch_signal( $signal_name, $callback_sub );

The callback subroutine is invoked when the process receives the named
signal. The returned id uniquely identifies the watcher and can be passed
to L</unwatch_signal>

=head2 C<unwatch_signal>

   $loop->unwatch_signal( $signal_name, $attach_id );

Remove the specified attachment from the list of callbacks watching the named
signal. If no attachment id is passed all callbacks are removed

=head2 C<watch_time>

   $loop->watch_time( $id, $callback_sub, $delay, $interval );

Invoke the callback subroutine after C<$delay> seconds. Repeat at C<$interval>
seconds. If the C<$interval> argument is either C<abs> or C<rel> then invoke
the callback only once. Requires a unique identifier

=head2 C<unwatch_time>

   $callback_sub = $loop->unwatch_time( $id );

Cancel the callback associated with the unique id

=head2 C<watch_write_handle>

   $loop->watch_write_handle( $file_handle, $callback_sub );

The callback subroutine is invoked when the file handle becomes writable

=head2 C<unwatch_write_handle>

   $loop->unwatch_write_handle( $file_handle );

Delete the file handle watcher for the specified file handle

=head2 C<uuid>

   $unique_integer = $loop->uuid;

Stateful counter. Returns a continuously incrementing integer

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<AnyEvent>

=item L<Async::Interrupt>

=item L<Class::Usul>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module. Please report problems to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=Async-IPC.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 Author

Peter Flanigan, C<< <pjfl@cpan.org> >>

=head1 License and Copyright

Copyright (c) 2014 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
