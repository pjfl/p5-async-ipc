package Async::IPC::Channel;

use namespace::autoclean;

use Async::IPC::Functions  qw( log_debug log_error read_error read_exactly );
use Class::Usul::Constants qw( FALSE NUL TRUE );
use Class::Usul::Functions qw( ensure_class_loaded nonblocking_write_pipe_pair
                               throw );
use Class::Usul::Types     qw( ArrayRef CodeRef FileHandle Maybe Object );
use English                qw( -no_match_vars );
use Type::Utils            qw( enum );
use Moo;

extends q(Async::IPC::Base);

my $CODEC_TYPE = enum 'CODEC_TYPE' => [ 'Sereal', 'Storable' ];
my $MODE_TYPE  = enum 'MODE_TYPE'  => [ 'async', 'sync' ];

# Private methods
my $_build_decode = sub {
   my $self = shift;

   if ($self->codec eq 'Sereal') {
      ensure_class_loaded 'Sereal::Decoder'; my $decoder = Sereal::Decoder->new;
      return sub { $decoder->decode( $_[ 0 ] ) };
   }

   ensure_class_loaded 'Storable'; return \&Storable::thaw;
};

my $_build_encode = sub {
   my $self = shift;

   if ($self->codec eq 'Sereal') {
      ensure_class_loaded 'Sereal::Encoder'; my $encoder = Sereal::Encoder->new;
      return sub { $encoder->encode( $_[ 0 ] ) };
   }

   ensure_class_loaded 'Storable'; return \&Storable::freeze;
};

my $_maybe_close_read_handle = sub {
   my $self = shift;

   if ($self->read_handle) {
      close $self->read_handle; $self->_set_read_handle( undef );
   }

   return;
};

my $_maybe_close_write_handle = sub {
   my $self = shift;

   if ($self->write_handle) {
      close $self->write_handle; $self->_set_write_handle( undef );
   }

   return;
};

my $_on_stream_read = sub {
   my ($self, $stream, $buf_ref, $eof) = @_; $self or return;

   if ($eof) {
      while (my $on_result = shift @{ $self->result_queue }) {
         $on_result->( $self, 'eof' );
      }

      $self->maybe_invoke_event( 'on_eof' );
      return;
   }

   length ${ $buf_ref } >= 4 or return FALSE;

   my $len = unpack 'I', ${ $buf_ref };

   length ${ $buf_ref } >= 4 + $len or return FALSE;

   my $record = $self->decode->( substr ${ $buf_ref }, 4, $len );

   substr( ${ $buf_ref }, 0, 4 + $len) = NUL; # Truncate on the left

   my $result = shift @{ $self->result_queue };

   $result and return $result->( $self, 'recv', $record );

   return $self->invoke_event( 'on_recv', $record );
};

my $_recv_async = sub {
   my ($self, %args) = @_;

   my $on_recv = $args{on_recv}; my $on_eof = $args{on_eof};

   my $f; not defined wantarray or $f = $self->factory->new_future;

   push @{ $self->result_queue }, sub {
      my ($self, $type, $record) = @_;

      if ($type eq 'recv') {
         $f and not $f->is_cancelled and $f->done( $record );
         $on_recv and $on_recv->( $self, $record );
      }
      elsif ($type eq 'eof') {
         $f and not $f->is_cancelled
            and $f->fail( 'EOF waiting for Channel recv', 'eof' );
         $on_eof and $on_eof->( $self );
      }
   };

   return $f;
};

my $_recv_sync = sub {
   my $self = shift;
   my $red  = read_exactly $self->read_handle, my $len, 4; # Block here

   read_error $self, $red and return;
   $red = read_exactly $self->read_handle, my $bytes, unpack 'I', $len;
   read_error $self, $red and return;

   return $self->decode->( $bytes );
};

my $_send_frozen = sub {
   my ($self, $record) = @_; my $bytes = (pack 'I', length $record).$record;

   $self->write_mode eq 'async' and return $self->stream->write( $bytes );

   my $len = syswrite $self->write_handle, $bytes, length $bytes;

   if (defined $len) { log_debug $self, "Wrote ${len} bytes" }
   else { log_error $self, $OS_ERROR }

   return $len;
};

my $_build_stream = sub {
   my $self = shift; return $self->factory->new_notifier
      (  type         => 'stream',
         autoflush    => TRUE,
         autostart    => FALSE,
         description  => $self->description.' stream',
         name         => $self->name.'_stream',
         on_read      => $self->capture_weakself( $_on_stream_read ),
         read_handle  => $self->read_handle,
         write_handle => $self->write_handle, );
};

# Public attributes
has '+autostart'   => default => FALSE;

has 'codec'        => is => 'ro',   isa => $CODEC_TYPE, default => 'Storable';

has 'decode'       => is => 'lazy', isa => CodeRef, builder => $_build_decode;

has 'encode'       => is => 'lazy', isa => CodeRef, builder => $_build_encode;

has 'handle_pair'  => is => 'lazy', isa => ArrayRef,
   builder         => sub { nonblocking_write_pipe_pair() };

has 'on_eof'       => is => 'ro',   isa => Maybe[CodeRef];

has 'on_recv'      => is => 'ro',   isa => Maybe[CodeRef];

has 'read_handle'  => is => 'rwp',  isa => Maybe[FileHandle],
   builder         => sub { $_[ 0 ]->handle_pair->[ 0 ] }, lazy => TRUE;

has 'read_mode'    => is => 'lazy', isa => $MODE_TYPE, default => 'sync';

has 'result_queue' => is => 'ro',   isa => ArrayRef, builder => sub { [] };

has 'stream'       => is => 'lazy', isa => Object,   builder => $_build_stream;

has 'write_handle' => is => 'rwp',  isa => Maybe[FileHandle],
   builder         => sub { $_[ 0 ]->handle_pair->[ 1 ] }, lazy => TRUE;

has 'write_mode'   => is => 'ro',   isa => $MODE_TYPE, default => 'sync';

# Construction
sub BUILD {
   my $self = shift; $self->read_handle; $self->write_handle; return;
}

sub DEMOLISH {
   my ($self, $gd) = @_; $gd and return; $self->close; return;
}

# Public methods
sub close {
   my $self = shift;

  ($self->read_mode eq 'async' or $self->write_mode eq 'async')
     and return $self->stream->close;

   $self->$_maybe_close_read_handle;
   $self->$_maybe_close_write_handle;
   return;
}

sub recv {
   my ($self, @args) = @_;

   $self->read_mode eq 'async' and return $self->$_recv_async( @args );

   return $self->$_recv_sync( @args );
}

sub send {
   return $_[ 0 ]->$_send_frozen( $_[ 0 ]->encode->( $_[ 1 ] ) );
}

sub stop {
   my ($self, $dirn) = @_;

   if    ($dirn eq 'read' ) {
      $self->read_mode eq 'async' and return $self->stream->stop;
   }
   elsif ($dirn eq 'write') {
      $self->write_mode eq 'async' and return $self->stream->stop;
   }
   else { throw 'A channel must stop either read or write' }

   return TRUE;
}

sub start {
   my ($self, $dirn) = @_;

   if    ($dirn eq 'read' ) {
      $self->$_maybe_close_write_handle;
      $self->read_mode eq 'async' and return $self->stream->start;
   }
   elsif ($dirn eq 'write') {
      $self->$_maybe_close_read_handle;
      $self->write_mode eq 'async' and return $self->stream->start;
   }
   else { throw 'A channel must start either read or write' }

   return TRUE;
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

Copyright (c) 2015 Peter Flanigan. All rights reserved

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
