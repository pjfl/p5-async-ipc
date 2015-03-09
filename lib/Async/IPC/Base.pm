package Async::IPC::Base;

use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader );
use Class::Usul::Constants qw( FALSE TRUE );
use Class::Usul::Functions qw( is_coderef throw );
use Class::Usul::Types     qw( BaseType Bool NonEmptySimpleStr
                               Object PositiveInt );
use Scalar::Util           qw( blessed weaken );

# Public attributes
has 'autostart'   => is => 'ro',   isa => Bool,               default => TRUE;

has 'description' => is => 'ro',   isa => NonEmptySimpleStr, required => TRUE;

has 'loop'        => is => 'rwp',  isa => Object,            required => TRUE;

has 'name'        => is => 'ro',   isa => NonEmptySimpleStr, required => TRUE;

has 'pid'         => is => 'rwp',  isa => PositiveInt,        default => 0;

# Private attributes
has '_usul'       => is => 'ro',   isa => BaseType,
   handles        => [ qw( config debug lock log run_cmd ) ],
   init_arg       => 'builder', required => TRUE;

sub can_event {
   my ($self, $ev_name) = @_;

   return ($self->can( $ev_name ) && $self->$ev_name);
}

sub capture_weakself {
   my ($self, $code) = @_; weaken $self;

   is_coderef $code or $self->can( $code ) or throw
      'Package [_1] cannot locate method [_2]', [ blessed $self, $code ];

   return sub {
      $self or return; my $cb = (is_coderef $code) ? $code : $self->$code;

      unshift @_, $self; goto &$cb;
   };
}

sub invoke_event {
   my ($self, $ev_name, @args) = @_;

   my $code = $self->can_event( $ev_name )
      or throw 'Event [_1] unknown', [ $ev_name ];

   my $lead = log_leader 'debug', $self->name, $self->pid;

   $self->log->debug( "${lead}Invoke event ${ev_name}" );

   return $code->( $self, @args );
}

sub maybe_invoke_event {
   my ($self, $ev_name, @args) = @_;

   my $code = $self->can_event( $ev_name ) or return FALSE;
   my $lead = log_leader 'debug', $self->name, $self->pid;

   $self->log->debug( "${lead}Invoke event ${ev_name}" );

   return $code->( $self, @args );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Base - Attributes common to each of the notifier classes

=head1 Synopsis

   use Moo;

   extends q(Async::IPC::Base);

=head1 Description

Base class for notifiers

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<autostart>

Read only boolean defaults to true. If false child process creation is delayed
until first use

=item C<description>

A required, immutable, non empty simple string. The description used by the
logger

=item C<loop>

An instance of L<Async::IPC::Loop>

=item C<name>

A required, immutable, non empty simple string. Logger key used to identify a
log entry

=item C<pid>

A non zero positive integer. The process id of this notifier

=back

=head1 Subroutines/Methods

=head2 C<can_event>

   $code_ref = $self->can_event( $event_name );

Returns the code reference of then handler if this object can handle the named
event, otherwise returns false

=head2 C<invoke_event>

   $result = $self->invoke_event( 'event_name', @args );

See L</maybe_invoke_event>

=head2 C<maybe_invoke_event>

   $result = $self->maybe_invoke_event( 'event_name', @args );

=head2 C<capture_weakself>

   $code_ref = $self->capture_weakself( $code_ref );

Returns a code reference which when called passes a weakened copy of C<$self>
to the supplied code reference

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
