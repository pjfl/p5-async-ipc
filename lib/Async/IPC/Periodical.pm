package Async::IPC::Periodical;

use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader );
use Class::Usul::Constants qw( TRUE );
use Class::Usul::Types     qw( CodeRef NonZeroPositiveInt SimpleStr Undef );
use Scalar::Util           qw( weaken );

extends q(Async::IPC::Base);

# Public attributes
has 'time_spec' => is => 'ro', isa => SimpleStr | Undef;

has 'code'      => is => 'ro', isa => CodeRef, required => TRUE;

has 'interval'  => is => 'ro', isa => NonZeroPositiveInt, default => 1;

# Construction
sub BUILD {
   my $self = shift; $self->autostart or return;

   if ($self->time_spec) { $self->once } else { $self->start }

   return;
}

# Public methods
sub once {
   my $self = shift; weaken( $self ); my $cb = sub { $self->code->( $self ) };

   my $flag = $self->time_spec or return $self->_time_spec_error;

   $self->loop->watch_time( $self->pid, $cb, $self->interval, $flag );
   return;
}

sub restart {
   my $self = shift; my $cb = $self->loop->unwatch_time( $self->pid );

   my $flag = $self->time_spec;

   $cb and $self->loop->watch_time( $self->pid, $cb, $self->interval, $flag );
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

# Private methdods
sub _build_pid {
   return $_[ 0 ]->loop->uuid;
}

sub _time_spec_error {
   my $self = shift; my $lead = log_leader 'error', $self->log_key, $self->pid;

   $self->log->error( "${lead}Flag time_spec must be set" );
   return;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Periodical - One-line description of the modules purpose

=head1 Synopsis

   use Async::IPC::Periodical;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head1 Diagnostics

=head1 Dependencies

=over 3

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
