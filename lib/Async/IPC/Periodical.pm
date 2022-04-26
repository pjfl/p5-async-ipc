package Async::IPC::Periodical;

use namespace::autoclean;

use Async::IPC::Constants qw( EXCEPTION_CLASS FALSE TRUE );
use Async::IPC::Functions qw( log_debug throw );
use Async::IPC::Types     qw( Bool CodeRef NonZeroPositiveNum
                              SimpleStr Undef );
use English               qw( -no_match_vars );
use Unexpected::Functions qw( Unspecified );
use Moo;

extends q(Async::IPC::Base);

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

=cut

has 'code' => is => 'ro', isa => CodeRef, required => TRUE;

=item C<interval>

A non zero positive integer that defaults to one. Time in seconds between
invocations of the code reference

=cut

has 'interval' => is => 'ro', isa => NonZeroPositiveNum, default => 1;

=item C<is_running>

A boolean that defaults to false. Is set to true when the notifier starts.
Gets set to false by calling the C<stop> method. Read only with a private
setter

=cut

has 'is_running' => is => 'rwp', isa => Bool, default => FALSE;

=item C<pid>

This timer's id. Set automatically by default

=cut

has '+pid' => builder => sub { $_[0]->loop->uuid };

=item C<time_spec>

A simple string or undefined. If specified can be either the flag values C<abs>
or C<rel>. Determines whether the interval is an absolute or relative time
specification

=cut

has 'time_spec'  => is => 'ro',  isa => SimpleStr|Undef;

=back

=head1 Subroutines/Methods

=head2 C<BUILD>

It L<autostart|Async::IPC::Base/autostart> is true calls L</once> if
C<time_spec> is set, calls L</start> otherwise

=cut

sub BUILD {
   my $self = shift;

   return unless $self->autostart;

   if ($self->time_spec) { $self->once } else { $self->start }

   return;
}

=head2 C<DEMOLISH>

Stops the notifier when the object reference goes out of scope and is
destroyed

=cut

sub DEMOLISH {
   my ($self, $gd) = @_;

   return if $gd;

   $self->stop;
   return;
}

=head2 C<once>

   $timer->once;

Invoke the code reference once

=cut

sub once {
   my $self = shift;

   return if $self->is_running;

   my $time_spec = $self->time_spec or throw Unspecified, ['time_spec'];

   $self->_set_is_running(TRUE);

   my $code = $self->code;
   my $cb   = $self->capture_weakself(sub {
      my $self = shift;

      $code->($self);
      $self->_set_is_running(FALSE)
   });

   $self->loop->watch_time($self->pid, $cb, $self->interval, $time_spec);
   return TRUE;
}

=head2 C<restart>

   $timer->restart;

Cancel and restart the timer

=cut

sub restart {
   my $self = shift;

   return unless $self->is_running;

   my $cb = $self->loop->unwatch_time($self->pid);

   $self->loop->watch_time(
      $self->pid, $cb, $self->interval, $self->time_spec
   ) if $cb;

   return TRUE;
}

=head2 C<start>

   $timer->start;

Call the code reference at C<interval> seconds

=cut

sub start {
   my $self = shift;

   return if $self->is_running;

   $self->_set_is_running(TRUE);
   log_debug $self, 'Starting '.$self->description;

   my $cb = $self->capture_weakself($self->code);

   $self->loop->watch_time($self->pid, $cb, $self->interval);
   return TRUE;
}

=head2 C<stop>

   $timer->stop;

Cancel the timer

=cut

sub stop {
   my $self = shift;

   return unless $self->is_running;

   log_debug $self, 'Stopping '.$self->description;
   $self->loop->unwatch_time($self->pid);
   $self->_set_is_running(FALSE);
   return TRUE;
}

1;

__END__

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
