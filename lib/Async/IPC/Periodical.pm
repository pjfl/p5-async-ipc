package Async::IPC::Periodical;

use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader );
use Class::Usul::Constants qw( EXCEPTION_CLASS FALSE TRUE );
use Class::Usul::Functions qw( throw );
use Class::Usul::Types     qw( Bool CodeRef NonZeroPositiveInt
                               SimpleStr Undef );
use Scalar::Util           qw( weaken );
use Unexpected::Functions  qw( Unspecified );

extends q(Async::IPC::Base);

# Public attributes
has 'code'       => is => 'ro',  isa => CodeRef, required => TRUE;

has 'interval'   => is => 'ro',  isa => NonZeroPositiveInt, default => 1;

has 'is_running' => is => 'rwp', isa => Bool, default => FALSE;

has 'time_spec'  => is => 'ro',  isa => SimpleStr | Undef;

# Construction
sub BUILD {
   my $self = shift; $self->autostart or return;

   if ($self->time_spec) { $self->once } else { $self->start }

   return;
}

sub DEMOLISH {
   $_[ 0 ]->stop; return;
}

sub _build_pid {
   return $_[ 0 ]->loop->uuid;
}

# Public methods
sub once {
   my $self = shift; my $code = $self->code;

   $self->is_running and throw 'Process [_1] already running', [ $self->pid ];

   my $time_spec = $self->time_spec or throw Unspecified, [ 'time_spec' ];

   weaken( $self ); my $cb = sub {
      $code->( $self ); $self->_set_is_running( FALSE ); };

   $self->loop->watch_time( $self->pid, $cb, $self->interval, $time_spec );
   $self->_set_is_running( TRUE );
   return;
}

sub restart {
   my $self = shift; my $cb = $self->loop->unwatch_time( $self->pid );

   $cb and $self->loop->watch_time
      ( $self->pid, $cb, $self->interval, $self->time_spec );
   return;
}

sub start {
   my $self = shift; my $code = $self->code;

   $self->is_running and throw 'Process [_1] already running', [ $self->pid ];

   weaken( $self ); my $cb = sub { $code->( $self ) };

   $self->loop->watch_time( $self->pid, $cb, $self->interval );
   $self->_set_is_running( TRUE );
   return;
}

sub stop {
   my $self = shift;

   $self->is_running or return FALSE; $self->_set_is_running( FALSE );

   my $lead = log_leader 'debug', $self->name, $self->pid;

   $self->log->debug( "${lead}Stopping ".$self->description );
   $self->loop->unwatch_time( $self->pid );
   return;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Periodical - Invoke subroutines at timed intervals

=head1 Synopsis

   use Async::IPC;

   my $factory = Async::IPC->new( builder => Class::Usul->new );

   my $timer = $factory->new_notifier
      (  code     => sub { ... code to run in a child process ... },
         interval => $clock_tick_interval,
         desc     => 'description used by the logger',
         key      => 'logger key used to identify a log entry',
         type     => 'periodical' );

   $timer->start;

=head1 Description

Invoke subroutines at timed intervals

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<code>

A required code reference. The callback subroutine to invoke at intervals

=item C<interval>

A non zero positive integer that defaults to one. Time in seconds between
invocations of the code reference

=item C<is_running>

A boolean that default to false. Is set to true when the notifier starts.
Gets set to false by calling the C<stop> method

=item C<time_spec>

A simple string or undefined. If specified can be either the flag values C<abs>
or C<rel>. Determines whether the interval a an absolute or relative time
specification

=back

=head1 Subroutines/Methods

=head2 C<BUILD>

It L<autostart|Async::IPC::Base/autostart> is true calls L</once> if
C<time_spec> is set, calls L</start> otherwise

=head2 C<DEMOLISH>

Stops the notifier when the object reference goes out of scope and is
destroyed

=head2 C<once>

   $timer->once;

Invoke the code reference once

=head2 C<restart>

   $timer->restart;

Cancel and restart the timer

=head2 C<start>

   $timer->start;

Call the code reference at C<interval> seconds

=head2 C<stop>

   $timer->stop;

Cancel the timer

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<Moo>

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
