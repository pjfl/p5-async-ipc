package Async::IPC::Handle;

use namespace::autoclean;

use Async::IPC::Constants qw( EXCEPTION_CLASS FALSE TRUE );
use Async::IPC::Functions qw( throw );
use Async::IPC::Types     qw( ArrayRef Bool CodeRef FileHandle Maybe Object );
use IO::Handle;
use Unexpected::Functions qw( Unspecified );
use Moo;

extends q(Async::IPC::Base);

has 'close_futures'   => is => 'ro',   isa => ArrayRef[Object],
   builder            => sub { [] };

has 'is_closing'      => is => 'rwp',  isa => Bool, default => FALSE;

has 'is_running'      => is => 'rwp',  isa => Bool, default => FALSE;

has 'on_closed'       => is => 'ro',   isa => Maybe[CodeRef];

has 'on_read_ready'   => is => 'lazy', isa => Maybe[CodeRef];

has 'on_write_ready'  => is => 'lazy', isa => Maybe[CodeRef];

has 'read_handle'     => is => 'rwp',  isa => Maybe[FileHandle];

has 'want_readready'  => is => 'rw',   isa => Bool, default => FALSE,
   trigger            => \&_toggle_read_watcher;

has 'want_writeready' => is => 'rw',   isa => Bool, default => FALSE,
   trigger            => \&_toggle_write_watcher;

has 'write_handle'    => is => 'rwp',  isa => Maybe[FileHandle];

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_;

   my $attr         = $orig->($self, @args);
   my $read_fileno  = delete $attr->{read_fileno};
   my $write_fileno = delete $attr->{write_fileno};

   if (defined $read_fileno && defined $write_fileno
       && $read_fileno == $write_fileno) {
      $attr->{handle} = IO::Handle->new_from_fd($read_fileno, 'r+');
   }
   else {
      $attr->{read_handle } = IO::Handle->new_from_fd($read_fileno,  'r')
         if defined $read_fileno;
      $attr->{write_handle} = IO::Handle->new_from_fd($write_fileno, 'w')
         if defined $write_fileno;
   }

   my $handle = delete $attr->{handle};

   $attr->{read_handle} = $attr->{write_handle} = $handle if defined $handle;

   return $attr;
};

sub BUILD {
   my $self = shift;

   $self->start if $self->autostart;

   return;
}

sub DEMOLISH {
   my ($self, $gd) = @_;

   return if $gd;

   $self->close;
   return;
}

# Public methods
sub close {
   my $self = shift;

   return TRUE if $self->is_closing;

   $self->_set_is_closing(TRUE);
   $self->stop;

   my $read_handle = $self->read_handle;

   close $read_handle if defined $read_handle;

   $self->_set_read_handle(undef);

   my $write_handle = $self->write_handle;

   close $write_handle if defined $write_handle;

   $self->_set_write_handle(undef);

   my $rv = $self->maybe_invoke_event('on_closed');

   if ($self->close_futures) {
      $_->done for (@{$self->close_futures});
   }

   return (defined $rv) ? $rv : TRUE;
}

sub new_close_future {
   my $self = shift;

   push @{$self->close_futures}, my $future = $self->factory->new_future;

   $future->on_cancel($self->capture_weakself(sub {
      my ($self, $f) = @_;

      return unless $self;

      @{$self->close_futures} = grep { $_ != $f } @{$self->close_futures};
   }));

   return $future;
}

sub set_handle {
   my ($self, $handle) = @_;

   $self->stop;
   $self->_set_read_handle($handle);
   $self->_set_write_handle($handle);

   $self->start if $self->autostart;

   return;
}

sub set_handles {
   my ($self, %params) = @_;

   $self->stop;
   $self->_set_read_handle($params{read_handle }) if $params{read_handle};
   $self->_set_write_handle($params{write_handle}) if $params{write_handle};
   $self->start if $self->autostart;
   return;
}

sub start {
   my $self    = shift;
   my $started = FALSE;

   return if $self->is_running;

   $self->_set_is_running(TRUE);
   $self->_set_is_closing(FALSE);

   if ($self->read_handle && $self->on_read_ready) {
      $self->want_readready(TRUE);
      $started = TRUE;
   }

   if ($self->write_handle && $self->on_write_ready) {
      $self->want_writeready(TRUE);
      $started = TRUE;
   }

   return $started;
}

sub stop {
   my $self    = shift;
   my $stopped = FALSE;

   return unless $self->is_running;

   $self->_set_is_running(FALSE);

   if ($self->read_handle) {
      $self->want_readready(FALSE);
      $stopped = TRUE;
   }

   if ($self->write_handle) {
      $self->want_writeready(FALSE);
      $stopped = TRUE;
   }

   return $stopped;
}

# Private methods
sub _toggle_read_watcher {
   my ($self, $want) = @_;

   return unless defined $want;

   my $loop = $self->loop;

   throw Unspecified, ['read handle'] unless defined $self->read_handle;

   if ($want && !$loop->watching_read_handle($self->read_handle)) {
      throw Unspecified, ['on read ready'] unless defined $self->on_read_ready;

      my $cb = $self->capture_weakself('on_read_ready');

      $loop->watch_read_handle($self->read_handle, $cb);
   }
   else { $loop->unwatch_read_handle($self->read_handle) }

   return;
}

sub _toggle_write_watcher  {
   my ($self, $want) = @_;

   return unless defined $want;

   my $loop = $self->loop;

   throw Unspecified, ['write handle'] unless defined $self->write_handle;

   if ($want && !$loop->watching_write_handle($self->write_handle)) {
      throw Unspecified, ['on write ready']
         unless defined $self->on_write_ready;

      my $cb = $self->capture_weakself('on_write_ready');

      $loop->watch_write_handle($self->write_handle, $cb);
   }
   else { $loop->unwatch_write_handle($self->write_handle) }

   return;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Handle - Asyncronous inter process communication

=head1 Synopsis

   use Async::IPC::Handle;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<close_futures>

=item C<is_closing>

=item C<is_running>

=item C<on_closed>

=item C<on_read_ready>

=item C<on_write_ready>

=item C<read_handle>

=item C<write_handle>


=back

=head1 Subroutines/Methods

=head2 C<BUILD>


=head2 C<BUILDARGS>

=head2 C<DEMOLISH>

=head2 C<close>

=head2 C<new_close_future>

=head2 C<set_handle>

=head2 C<set_handles>

=head2 C<start>

=head2 C<stop>

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
