package Async::IPC::Loop;

use strictures;

use AnyEvent;
use Async::Interrupt;
use Async::IPC::Functions qw( to_hashref );
use English               qw( -no_match_vars );
use List::Util            qw( any );
use Scalar::Util          qw( blessed weaken );

my $Cache = {};
my $UUID  = 1;

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

=cut

sub new {
   my ($proto, @args) = @_;

   my $class = blessed $proto || $proto;

   return bless to_hashref(@args), $class;
}

=head2 C<once>

   $loop->once( $timeout, $callback_sub );

Process events once and then return. The optional time out and callback
subroutine is used to terminate the waiting for events after a given time

=cut

sub once {
   my ($self, $tmout, $cb) = @_;

   $cb //= sub {};

   my $w = AnyEvent->timer(after => $tmout, cb => $cb) if defined $tmout;

   AnyEvent->_poll; # Undocumented method
   return;
}

=head2 C<start>

   $loop->start;

Enter into the event loop. Wait here, processing events until the event loop
is terminated

=cut

sub start {
   my $self = shift;
   my $cv   = $self->_events('condvars');

   return (local $cv->{state} = AnyEvent->condvar)->recv;
}

=head2 C<start_nb>

   $loop->start_nb;

Same a L</start> but returns immediately

=cut

sub start_nb {
   my ($self, $cb) = @_;

   my $cv = $self->_events('condvars');

   (local $cv->{state} = AnyEvent->condvar)->cb(sub {
      my $self = shift;
      my @res  = $self->recv;

      $cb->(@res) if defined $cb;
   });

   return;
}

=head2 C<stop>

   $loop->stop;

Terminate the event loop. When this is called the L</start> method returns

=cut

sub stop {
   my ($self, @args) = @_;

   my $cv = $self->_events('condvars');

   $cv->{state}->send(@args) if exists $cv->{state} && defined $cv->{state};

   return;
}

=head2 C<watch_child>

   $loop->watch_child( $process_id, $callback_sub );

If the process id is greater than zero, the callback subroutine is invoked
when the process exits.

If the process id is zero and there is no callback subroutine, wait for all
child processes to exit. If the callback subroutine is supplied then, when
called, it should return the list of process ids to wait for

=cut

sub watch_child {
   my ($self, $id, $cb) = @_;

   my $w = $self->_events('watchers');

   if ($id) {
      my $cv = $w->{$id}->[0] = AnyEvent->condvar;

      $w->{$id}->[1] = AnyEvent->child(pid => $id, cb => sub {
         $cb->(@_) if defined $cb;
         $cv->send;
      });
   }
   else {
      for (sort { $a <=> $b } $cb ? $cb->() : keys %{$w}) {
         $w->{$_}->[0]->recv if $w->{$_} && $w->{$_}->[0];
         $self->unwatch_child($_);
      }
   }

   return;
}

=head2 C<watching_child>

   $bool = $loop->watching_child( $process_id );

Returns true if the specified process is being watched, false otherwise

=cut

sub watching_child {
   my ($self, $id) = @_;

   my $w = $self->_events('watchers');

   return ((exists $w->{$id}) && (defined $w->{$id})) ? 1 : 0;
}

=head2 C<unwatch_child>

   $loop->unwatch_child( $process_id );

Delete the child watcher for the specified process

=cut

sub unwatch_child {
   my ($self, $id) = @_;

   my $w = $self->_events('watchers');

   undef $w->{$id}->[0];
   undef $w->{$id}->[1];
   delete $w->{$id};
   return;
}

=head2 C<watch_idle>

   $loop->watch_idle( $id, $callback_sub );

Executes the callback after any pending events have been processed

=cut

sub watch_idle {
   my ($self, $id, $cb) = @_;

   my $i = $self->_events('idle');

   $i->{$id} = AnyEvent->idle(cb => sub {
      delete $i->{$id};
      $cb->(@_);
   });

   return;
}

=head2 C<watching_idle>

   $bool = $loop->watching_idle( $id );

Returns true if the specified id is an idle watcher, false otherwise

=cut

sub watching_idle {
   my ($self, $id) = @_;

   my $i = $self->_events('idle');

   return ((exists $i->{$id}) && (defined $i->{$id})) ? 1 : 0;
}

=head2 C<unwatch_idle>

   $loop->unwatch_idle( $id );

Delete the idle watcher for the specified id

=cut

sub unwatch_idle {
   my ($self, $id) = @_;

   delete $self->_events('idle')->{$id};
   return;
}

=head2 C<watch_read_handle>

   $loop->watch_read_handle( $file_handle, $callback_sub );

The callback subroutine is invoked when the file handle becomes readable

=cut

sub watch_read_handle {
   my ($self, $fh, $cb) = @_;

   my $h = $self->_events('handles');

   $h->{"r${fh}"} = AnyEvent->io(cb => $cb, fh => $fh, poll => 'r');
   return;
}

=head2 C<watching_read_handle>

   $bool = $loop->watching_read_handle( $file_handle );

Returns true if the file handle is being watched for reading, false otherwise

=cut

sub watching_read_handle {
   my ($self, $fh) = @_;

   my $h = $self->_events('handles');

   return ((exists $h->{"r${fh}"}) && (defined $h->{"r${fh}"})) ? 1 : 0;
}

=head2 C<unwatch_read_handle>

   $loop->unwatch_read_handle( $file_handle );

Delete the file handle watcher for the specified file handle

=cut

sub unwatch_read_handle {
   my ($self, $fh) = @_;

   delete $self->_events('handles')->{"r${fh}"};
   return;
}

=head2 C<watch_signal>

   $attach_id = $loop->watch_signal( $signal_name, $callback_sub );

The callback subroutine is invoked when the process receives the named
signal. The returned id uniquely identifies the watcher and can be passed
to L</unwatch_signal>

=cut

sub watch_signal {
   my ($self, $signal, $cb) = @_;

   my $loop = $self; weaken( $loop );
   my $attaches;

   unless ($attaches = $self->_sigattaches->{$signal}) {
      my $s = $self->_events('signals');

      $s->{$signal} = AnyEvent->signal(signal => $signal, cb => sub {
         my @attaches = @{$loop->_sigattaches->{$signal} // [] };

         for my $attachment (@attaches) { $attachment->() }
      });

      $attaches = $self->_sigattaches->{$signal} = [];
   }

   push @{$attaches}, $cb;
   return \$attaches->[-1];
}

=head2 C<watching_signal>

   $bool = $loop->watching_signal( $signal_name, $optional_attach_id );

Returns true if the signal is being watched, false otherwise. If the
C<$optional_attach_id> is supplied tests to see if the signal has
that attach callback

=cut

sub watching_signal {
   my ($self, $signal, $id) = @_;

   my $s = $self->_events('signals');
   my $watching = (exists $s->{$signal}) && (defined $s->{$signal});

   return $watching ? 1 : 0 if !$watching || !defined $id;

   return any { $_ == $id }, map { \$_ } @{$self->_sigattaches->{$signal}};
}

=head2 C<unwatch_signal>

   $loop->unwatch_signal( $signal_name, $attach_id );

Remove the specified attachment from the list of callbacks watching the named
signal. If no attachment id is passed all callbacks are removed

=cut

sub unwatch_signal {
   my ($self, $signal, $id) = @_;

   # Can't use grep because we have to preserve the addresses
   my $attaches = $self->_sigattaches->{$signal} or return;

   for (my $i = 0; $i < @{$attaches}; ) {
      next if !$id && splice @{$attaches}, $i, 1, ();

      last if ($id == \$attaches->[$i]) && splice @{$attaches}, $i, 1, ();

      $i++;
   }

   return if scalar @{$attaches};

   delete $self->_sigattaches->{$signal};
   delete $self->_events('signals')->{$signal};
   return;
}

=head2 C<watch_time>

   $loop->watch_time( $id, $callback_sub, $delay, $interval );

Invoke the callback subroutine after C<delay> seconds. Repeat at C<interval>
seconds. If the C<interval> argument is either C<abs> or C<rel> then invoke
the callback only once. Requires a unique identifier

=cut

sub watch_time {
   my ($self, $id, $cb, $after, $interval) = @_;

   if (defined $interval) {
      $after -= AnyEvent->now if $interval eq 'abs';

      $interval = 0 if $interval =~ m{ \A (?: abs | rel ) \z }mx;
   }

   $after = 0 unless $after > 0;

   my @args = (after => $after, cb => $cb);

   push @args, 'interval', $after unless defined $interval;

   push @args, 'interval', $interval if $interval;

   my $t = $self->_events('timers');

   $t->{$id}->[0] = $cb; # So that unwatch_time can return the cb
   $t->{$id}->[1] = AnyEvent->timer(@args);
   return;
}

=head2 C<watching_time>

   $bool = $loop->watching_time( $id );

Returns true if the specified id is time watching identifier, false otherwise

=cut

sub watching_time {
   my ($self, $id) = @_;

   my $t = $self->_events('timers');

   return ((exists $t->{$id}) && (defined $t->{$id})) ? 1 : 0;
}

=head2 C<unwatch_time>

   $callback_sub = $loop->unwatch_time( $id );

Cancel the callback associated with the unique id

=cut

sub unwatch_time {
   my ($self, $id) = @_;

   my $t = $self->_events('timers');

   return 0 unless exists $t->{$id};

   my $cb = $t->{$id}->[0];

   undef $t->{$id}->[0];
   undef $t->{$id}->[1];
   delete $t->{$id};

   return $cb;
}

=head2 C<watch_write_handle>

   $loop->watch_write_handle( $file_handle, $callback_sub );

The callback subroutine is invoked when the file handle becomes writable

=cut

sub watch_write_handle {
   my ($self, $fh, $cb) = @_;

   my $h = $self->_events('handles');

   $h->{"w${fh}"} = AnyEvent->io(cb => $cb, fh => $fh, poll => 'w');

   return;
}

=head2 C<watching_write_handle>

   $bool = $loop->watching_write_handle( $file_handle );

Returns true if the file handle is being watched for writing, false otherwise

=cut

sub watching_write_handle {
   my ($self, $fh) = @_;

   my $h = $self->_events('handles');

   return ((exists $h->{"w${fh}"}) && (defined $h->{"w${fh}"})) ? 1 : 0;
}

=head2 C<unwatch_write_handle>

   $loop->unwatch_write_handle( $file_handle );

Delete the file handle watcher for the specified file handle

=cut

sub unwatch_write_handle {
   my ($self, $fh) = @_;

   delete $self->_events('handles')->{"w${fh}"};
   return;
}

=head2 C<uuid>

   $unique_integer = $loop->uuid;

Stateful counter. Returns a continuously incrementing integer

=cut

sub uuid {
   return $UUID++;
}

# Private methods
sub _events { # Do not share state between forks
   return $Cache->{$PID}->{$_[1]} ||= {};
}

sub  _log { # Unused but included for debugging
   return $_[0]->{builder}->log;
}

sub _sigattaches {
   return $Cache->{$PID}->{'sigattaches'} ||= {};
}

1;

__END__

=head1 Diagnostics

The C<_log> method is provided for debugging purposes

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

Copyright (c) 2016 Peter Flanigan. All rights reserved

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
