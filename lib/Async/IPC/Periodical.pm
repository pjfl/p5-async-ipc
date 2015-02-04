package Async::IPC::Periodical;

use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader );
use Class::Usul::Constants qw( TRUE );
use Class::Usul::Types     qw( CodeRef NonZeroPositiveInt SimpleStr Undef );
use Scalar::Util           qw( weaken );

extends q(Async::IPC::Base);

# Public attributes
has 'code'      => is => 'ro', isa => CodeRef, required => TRUE;

has 'interval'  => is => 'ro', isa => NonZeroPositiveInt, default => 1;

has 'time_spec' => is => 'ro', isa => SimpleStr | Undef;

# Private methdods
my $_time_spec_error = sub {
   my $self = shift; my $lead = log_leader 'error', $self->log_key, $self->pid;

   $self->log->error( "${lead}Flag time_spec must be set" );
   return;
};

# Construction
sub BUILD {
   my $self = shift; $self->autostart or return;

   if ($self->time_spec) { $self->once } else { $self->start }

   return;
}

sub _build_pid {
   return $_[ 0 ]->loop->uuid;
}

# Public methods
sub once {
   my $self = shift; weaken( $self ); my $cb = sub { $self->code->( $self ) };

   my $time_spec = $self->time_spec or return $self->$_time_spec_error;

   $self->loop->watch_time( $self->pid, $cb, $self->interval, $time_spec );
   return;
}

sub restart {
   my $self = shift; my $cb = $self->loop->unwatch_time( $self->pid );

   $cb and $self->loop->watch_time
      ( $self->pid, $cb, $self->interval, $self->time_spec );
   return;
}

sub start {
   my $self = shift; weaken( $self ); my $cb = sub { $self->code->( $self ) };

   $self->loop->watch_time( $self->pid, $cb, $self->interval );
   return;
}

sub stop {
   my $self = shift; my $lead = log_leader 'debug', $self->log_key, $self->pid;

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

=item C<time_spec>

A simple string or undefined. If specified can be either the flag values C<abs>
or C<rel>. Determines whether the interval a an absolute or relative time
specification

=back

=head1 Subroutines/Methods

=head2 C<BUILD>

It L<autostart|Async::IPC::Base/autostart> is true calls L</once> if
C<time_spec> is set, calls L</start> otherwise

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
