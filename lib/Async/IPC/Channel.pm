package Async::IPC::Channel;

use namespace::autoclean;

use Async::IPC::Constants qw( FALSE NUL TRUE );
use Async::IPC::Functions qw( ensure_class_loaded log_debug log_error
                              read_error read_exactly socket_pair throw );
use Async::IPC::Types     qw( ArrayRef CodeRef FileHandle Maybe Object );
use English               qw( -no_match_vars );
use Type::Utils           qw( enum );
use Moo;

extends q(Async::IPC::Base);

my $CODEC_TYPE = enum 'CODEC_TYPE' => [ 'Sereal', 'Storable' ];
my $MODE_TYPE  = enum 'MODE_TYPE'  => [ 'async', 'sync' ];

# Public attributes
has '+autostart'   => default => FALSE;

has 'codec'        => is => 'ro',   isa => $CODEC_TYPE, default => 'Storable';

has 'decode'       => is => 'lazy', isa => CodeRef, builder => '_build_decode';

has 'encode'       => is => 'lazy', isa => CodeRef, builder => '_build_encode';

has 'handle_pair'  => is => 'lazy', isa => ArrayRef,
   builder         => sub { socket_pair() };

has 'on_eof'       => is => 'ro',   isa => Maybe[CodeRef];

has 'on_recv'      => is => 'ro',   isa => Maybe[CodeRef];

has 'read_handle'  => is => 'rwp',  isa => Maybe[FileHandle],
   builder         => sub { $_[0]->handle_pair->[0] }, lazy => TRUE;

has 'read_mode'    => is => 'lazy', isa => $MODE_TYPE, default => 'sync';

has 'result_queue' => is => 'ro',   isa => ArrayRef, builder => sub { [] };

has 'stream'       => is => 'lazy', isa => Object, builder => '_build_stream';

has 'write_handle' => is => 'rwp',  isa => Maybe[FileHandle],
   builder         => sub { $_[0]->handle_pair->[1] }, lazy => TRUE;

has 'write_mode'   => is => 'ro',   isa => $MODE_TYPE, default => 'sync';

# Construction
sub BUILD {
   my $self = shift;

   $self->read_handle;
   $self->write_handle;
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

   return $self->stream->close
      if $self->read_mode eq 'async' || $self->write_mode eq 'async';

   $self->_maybe_close_read_handle;
   $self->_maybe_close_write_handle;
   return;
}

sub recv {
   my ($self, @args) = @_;

   return $self->_recv_async(@args) if $self->read_mode eq 'async';

   return $self->_recv_sync(@args);
}

sub send {
   my ($self, $args) = @_;

   return $self->_send_frozen($self->encode->($args));
}

sub stop {
   my ($self, $dirn) = @_;

   if ($dirn eq 'read') {
      return $self->stream->stop if $self->read_mode eq 'async';
   }
   elsif ($dirn eq 'write') {
      return $self->stream->stop if $self->write_mode eq 'async';
   }
   else { throw 'A channel must stop either read or write' }

   return TRUE;
}

sub start {
   my ($self, $dirn) = @_;

   if ($dirn eq 'read' ) {
      $self->_maybe_close_write_handle;

      return $self->stream->start if $self->read_mode eq 'async';
   }
   elsif ($dirn eq 'write') {
      $self->_maybe_close_read_handle;

      return $self->stream->start if $self->write_mode eq 'async';
   }
   else { throw 'A channel must start either read or write' }

   return TRUE;
}

# Private methods
sub _build_decode {
   my $self = shift;

   if ($self->codec eq 'Sereal') {
      ensure_class_loaded 'Sereal::Decoder';

      my $decoder = Sereal::Decoder->new;

      return sub { $decoder->decode($_[0]) };
   }

   ensure_class_loaded 'Storable';
   return \&Storable::thaw;
}

sub _build_encode {
   my $self = shift;

   if ($self->codec eq 'Sereal') {
      ensure_class_loaded 'Sereal::Encoder';

      my $encoder = Sereal::Encoder->new;

      return sub { $encoder->encode($_[0]) };
   }

   ensure_class_loaded 'Storable';
   return \&Storable::freeze;
}

sub _build_stream {
   my $self = shift;

   return $self->factory->new_notifier(
      type         => 'stream',
      autoflush    => TRUE,
      autostart    => FALSE,
      description  => $self->description.' stream',
      name         => $self->name.'_stream',
      on_read      => $self->capture_weakself(\&_on_stream_read),
      read_handle  => $self->read_handle,
      write_handle => $self->write_handle,
    );
}

sub _maybe_close_read_handle {
   my $self = shift;

   if ($self->read_handle) {
      CORE::close $self->read_handle;
      $self->_set_read_handle(undef);
   }

   return;
}

sub _maybe_close_write_handle {
   my $self = shift;

   if ($self->write_handle) {
      CORE::close $self->write_handle;
      $self->_set_write_handle(undef);
   }

   return;
}

sub _on_stream_read {
   my ($self, $stream, $buf_ref, $eof) = @_;

   return unless $self;

   if ($eof) {
      while (my $on_result = shift @{$self->result_queue}) {
         $on_result->($self, 'eof');
      }

      $self->maybe_invoke_event('on_eof');
      return;
   }

   return FALSE unless length ${$buf_ref } >= 4;

   my $len = unpack 'I', ${$buf_ref};

   return FALSE unless length ${$buf_ref} >= 4 + $len;

   my $record = $self->decode->(substr ${$buf_ref}, 4, $len);

   substr(${$buf_ref}, 0, 4 + $len) = NUL; # Truncate on the left

   my $result = shift @{$self->result_queue};

   return $result->($self, 'recv', $record) if $result;

   return $self->invoke_event('on_recv', $record);
}

sub _recv_async {
   my ($self, %args) = @_;

   my $on_recv = $args{on_recv};
   my $on_eof  = $args{on_eof};
   my $f; $f = $self->factory->new_future if defined wantarray;

   push @{$self->result_queue}, sub {
      my ($self, $type, $record) = @_;

      if ($type eq 'recv') {
         $f->done($record) if $f && !$f->is_cancelled;

         $on_recv->($self, $record) if $on_recv;
      }
      elsif ($type eq 'eof') {
         $f->fail('EOF waiting for Channel recv', 'eof')
            if $f && !$f->is_cancelled;

         $on_eof->($self) if $on_eof;
      }
   };

   return $f;
}

sub _recv_sync {
   my $self = shift;
   my $red  = read_exactly $self->read_handle, my $len, 4; # Block here

   return if read_error $self, $red;

   $red = read_exactly $self->read_handle, my $bytes, unpack 'I', $len;

   return if read_error $self, $red;

   return $self->decode->($bytes);
}

sub _send_frozen {
   my ($self, $record) = @_;

   my $bytes = (pack 'I', length $record).$record;

   return $self->stream->write($bytes) if $self->write_mode eq 'async';

   my $len = syswrite $self->write_handle, $bytes, length $bytes;

   if (defined $len) { log_debug $self, "Wrote ${len} bytes" }
   else { log_error $self, $OS_ERROR }

   return $len;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Channel - Asyncronous inter process communication

=head1 Synopsis

   use Async::IPC::Channel;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<autostart>

=item C<codec>

=item C<decode>

=item C<encode>

=item C<handle_pair>

=item C<on_eof>

=item C<on_recv>

=item C<read_handle>

=item C<read_mode>

=item C<result_queue>

=item C<stream>

=item C<write_handle>

=item C<write_mode>

=back

=head1 Subroutines/Methods

=head2 C<BUILD>

=head2 C<DEMOLISH>

=head2 C<close>

=head2 C<recv>

=head2 C<send>

=head2 C<stop>

=head2 C<start>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Async::IPC::Base>

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
