package Async::IPC::Base;

use namespace::autoclean;

use Moo;
use Async::IPC;
use Async::IPC::Functions  qw( log_debug );
use Class::Usul::Constants qw( FALSE TRUE );
use Class::Usul::Functions qw( is_coderef throw );
use Class::Usul::Types     qw( BaseType Bool CodeRef HashRef Maybe
                               NonEmptySimpleStr Object PositiveInt );
use English                qw( -no_match_vars );
use Scalar::Util           qw( blessed weaken );

my $Notifiers = {};

# Public attributes
has 'autostart'   => is => 'ro',   isa => Bool, default => TRUE;

has 'builder'     => is => 'ro',   isa => BaseType,
   handles        => [ qw( config debug lock log run_cmd ) ], required => TRUE;

has 'description' => is => 'ro',   isa => NonEmptySimpleStr, required => TRUE;

has 'factory'     => is => 'lazy', isa => Object, builder => sub {
   Async::IPC->new( builder => $_[ 0 ]->builder, loop => $_[ 0 ]->loop, ) };

has 'futures'     => is => 'ro',   isa => HashRef, builder => sub { {} };

has 'loop'        => is => 'ro',   isa => Object, required => TRUE;

has 'name'        => is => 'ro',   isa => NonEmptySimpleStr, required => TRUE;

has 'on_error'    => is => 'ro',   isa => Maybe[CodeRef];

has 'pid'         => is => 'rwp',  isa => PositiveInt, builder => sub { $PID },
   lazy           => TRUE;

has 'type'        => is => 'lazy', isa => NonEmptySimpleStr, builder => sub {
   my $class = blessed $_[ 0 ]; return lc ((split m{ :: }mx, $class)[ -1 ]);
};

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   my $desc = delete $attr->{desc}; $attr->{description} //= $desc;

   return $attr;
};

sub BUILD {
   my $self = shift; my $id = $self->type.'::'.$self->name;

   exists $Notifiers->{ $id } and $Notifiers->{ $id }
      and throw 'Notifier id [_1] not unique', [ $id ];

   $Notifiers->{ $id } = TRUE;
   return;
}

# Private methods
my $_can_event = sub {
   my ($self, $ev_name) = @_;

   return ($self->can( $ev_name ) && $self->$ev_name);
};

my $_invoke_event = sub {
   my ($self, $ev_name, $code, @args) = @_;

   log_debug $self, "Invoke event ${ev_name}";

   return $code->( $self, @args );
};

# Public methods
sub adopt_future {
   my ($self, $f) = @_; my $fkey = "$f"; # Stable stringification

   $self->futures->{ $fkey } = $f;

   $f->on_ready( $self->capture_weakself( sub {
      my ($self, $f) = @_; delete $self->futures->{ $fkey };

      $f->failure and $self->invoke_error( $f->failure );
   } ) );

   return $f;
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

sub invoke_error {
   my ($self, $message, $name, @details) = @_;

   $self->on_error or throw $message;

   return $self->on_error->( $self, $message, $name, @details );
}

sub invoke_event {
   my ($self, $ev_name, @args) = @_;

   my $code = $self->$_can_event( $ev_name )
      or throw 'Event [_1] unknown', [ $ev_name ];

   return $self->$_invoke_event( $ev_name, $code, @args );
}

sub maybe_invoke_event {
   my ($self, $ev_name, @args) = @_;

   my $code = $self->$_can_event( $ev_name ) or return;

   return $self->$_invoke_event( $ev_name, $code, @args );
}

sub replace_weakself {
   my ($self, $code) = @_; weaken $self;

   is_coderef $code or $self->can( $code ) or throw
      'Package [_1] cannot locate method [_2]', [ blessed $self, $code ];

   return sub {
      $self or return; my $cb = (is_coderef $code) ? $code : $self->$code;

      shift @_; unshift @_, $self; goto &$cb;
   };
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

=item C<builder>

A required instance of L<Class::Usul>. Provides object references for;
configuration, logging, locking, and localisation

=item C<description>

A required, immutable, non empty simple string. The description used by the
logger

=item C<futures>

=item C<loop>

An instance of L<Async::IPC::Loop>

=item C<name>

A required, immutable, non empty simple string. Logger key used to identify a
log entry

=item C<on_error>

=item C<pid>

A non zero positive integer. The process id of this notifier

=item C<type>

=back

=head1 Subroutines/Methods

=head2 C<BUILDARGS>

Allows C<desc> to be used as an alias for the C<description> attribute during
construction

=head2 C<BUILD>

=head2 C<adopt_future>

=head2 C<can_event>

   $code_ref = $self->can_event( $event_name );

Returns the code reference of then handler if this object can handle the named
event, otherwise returns false

=head2 C<capture_weakself>

   $code_ref = $self->capture_weakself( $code_ref );

Returns a code reference which when called passes a weakened copy of C<$self>
to the supplied code reference

=head2 C<invoke_error>

=head2 C<invoke_event>

   $result = $self->invoke_event( 'event_name', @args );

See L</maybe_invoke_event>

=head2 C<maybe_invoke_event>

   $result = $self->maybe_invoke_event( 'event_name', @args );

=head2 C<replace_weakself>

   $code_ref = $self->capture_weakself( $code_ref );

Like L</capture_weakself> but shifts the original invocant off the stack first

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
