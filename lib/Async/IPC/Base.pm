package Async::IPC::Base;

use namespace::autoclean;

use Async::IPC;
use Async::IPC::Constants qw( FALSE TRUE );
use Async::IPC::Functions qw( log_debug throw );
use Async::IPC::Types     qw( Bool Builder CodeRef HashRef Maybe
                              NonEmptySimpleStr Object PositiveInt );
use English               qw( -no_match_vars );
use Ref::Util             qw( is_coderef );
use Scalar::Util          qw( blessed weaken );
use Moo;

my $notifiers = {};

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

=cut

has 'autostart' => is => 'ro', isa => Bool, default => TRUE;

=item C<builder>

A required instance of the C<Builder> type defined in
L<Async::IPC::Types>. This injected dependency is satisfied by an instance of
L<Class::Usul> but could be provided by any object that satisfies the type
constraint.

Provides object references for; configuration, locking, and logging. Also
provides a boolean to turn on debugging and a method to run external commands

=cut

has 'builder' => is => 'ro', isa => Builder, required => TRUE,
   handles    => [ 'config', 'debug', 'lock', 'log', 'run_cmd' ];

=item C<description>

A required, immutable, non empty simple string. The description used by the
logger

=cut

has 'description' => is => 'ro', isa => NonEmptySimpleStr, required => TRUE;

=item C<factory>

An instance of L<Async::IPC> which this notifier can use to create other
notifiers

=cut

has 'factory' => is => 'lazy', isa => Object, builder => sub {
   return Async::IPC->new( builder => $_[0]->builder, loop => $_[0]->loop );
};

=item C<futures>

This hash reference is used to store any futures adopted by this notifier.
The reference to the future is deleted from the this hash reference if the
future fails

=cut

has 'futures' => is => 'ro', isa => HashRef, builder => sub { {} };

=item C<loop>

A required instance of L<Async::IPC::Loop>. Used to instantiate the L</factory>
attribute

=cut

has 'loop' => is => 'ro', isa => Object, required => TRUE;

=item C<name>

A required, immutable, non empty simple string. Logger key used to identify a
log entry

=cut

has 'name' => is => 'ro', isa => NonEmptySimpleStr, required => TRUE;

=item C<on_error>

This optional code references is invoked when a future fails

=cut

has 'on_error' => is => 'ro', isa => Maybe[CodeRef];

=item C<pid>

An immutable positive integer with a private setter. The process id of this
notifier

=cut

has 'pid'  => is => 'rwp', isa => PositiveInt, lazy => TRUE,
   builder => sub { $PID };

=item C<type>

The notifiers type attribute derived from the notifiers class name

=cut

has 'type' => is => 'lazy', isa => NonEmptySimpleStr, builder => sub {
   my $class = blessed $_[0]; return lc ((split m{ :: }mx, $class)[-1]);
};

=back

=cut

=head1 Subroutines/Methods

=head2 C<BUILDARGS>

Allows C<desc> to be used as an alias for the C<description> attribute during
construction

=cut

around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_;

   my $attr = $orig->($self, @args);
   my $desc = delete $attr->{desc}; $attr->{description} //= $desc;

   return $attr;
};

=head2 C<BUILD>

Raises an exception if the C<type> and C<name> attributes do not form a
unique reference

=cut

sub BUILD {
   my $self = shift;
   my $id   = $self->type.'::'.$self->name;

   throw 'Notifier id [_1] not unique', [$id]
      if exists $notifiers->{$id} && $notifiers->{$id};

   $notifiers->{$id} = TRUE;
   return;
}

=head2 C<adopt_future>

Installs a handler which will call C<invoke_error> if the future fails

=cut

sub adopt_future {
   my ($self, $f) = @_;

   my $fkey = "${f}"; # Stable stringification

   $self->futures->{$fkey} = $f;

   $f->on_ready($self->capture_weakself(sub {
      my $self = shift;
      my $f    = delete $self->futures->{$fkey};

      $self->invoke_error($f->failure) if $f->failure;
   }));

   return $f;
}

=head2 C<capture_weakself>

   $code_ref = $self->capture_weakself( $code_ref );

Returns a code reference which when called passes a weakened copy of C<$self>
to the supplied code reference

=cut

sub capture_weakself {
   my ($self, $code) = @_; weaken $self;

   throw 'Package [_1] cannot locate method [_2]', [ blessed $self, $code ]
      unless is_coderef($code) || $self->can($code);

   return sub {
      return unless $self;

      my $cb = is_coderef($code) ? $code : $self->$code;

      unshift @_, $self;
      goto &$cb;
   };
}

=head2 C<invoke_error>

Either raise an exception using the provided message, or if an C<on_error>
call back has been provided call that instead

=cut

sub invoke_error {
   my ($self, $message, $name, @details) = @_;

   throw $message unless $self->on_error;

   return $self->on_error->($self, $message, $name, @details);
}

=head2 C<invoke_event>

   $result = $self->invoke_event( 'event_name', @args );

See L</maybe_invoke_event>. Raises an exception if the event is not implemented

=cut

sub invoke_event {
   my ($self, $ev_name, @args) = @_;

   my $code = $self->_can_event($ev_name)
      or throw 'Event [_1] unknown', [ $ev_name ];

   return $self->_invoke_event($ev_name, $code, @args);
}

=head2 C<maybe_invoke_event>

   $result = $self->maybe_invoke_event( 'event_name', @args );

Call the matching event handler code reference if the event name exists as an
attribute of this notifier

=cut

sub maybe_invoke_event {
   my ($self, $ev_name, @args) = @_;

   my $code = $self->_can_event($ev_name) or return;

   return $self->_invoke_event($ev_name, $code, @args);
}

=head2 C<replace_weakself>

   $code_ref = $self->capture_weakself( $code_ref );

Like L</capture_weakself> but shifts the original invocant off the stack first

=cut

sub replace_weakself {
   my ($self, $code) = @_; weaken $self;

   throw 'Package [_1] cannot locate method [_2]', [ blessed $self, $code ]
      unless is_coderef($code) || $self->can($code);

   return sub {
      return unless $self;

      my $cb = is_coderef($code) ? $code : $self->$code;

      shift @_;
      unshift @_, $self;
      goto &$cb;
   };
}

# Returns the code reference of the handler if this object can handle the named
# event, otherwise returns false
sub _can_event {
   my ($self, $ev_name) = @_;

   return FALSE unless $self->can($ev_name);

   return $self->$ev_name;
}

sub _invoke_event {
   my ($self, $ev_name, $code, @args) = @_;

   log_debug $self, "Invoke event ${ev_name}";

   return $code->($self, @args);
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
