package Async::IPC::Channel;

use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader read_error read_exactly );
use Async::IPC::Stream;
use Class::Usul::Constants qw( FALSE NUL TRUE );
use Class::Usul::Functions qw( ensure_class_loaded nonblocking_write_pipe_pair
                               throw );
use Class::Usul::Types     qw( ArrayRef CodeRef FileHandle Maybe Object );
use English                qw( -no_match_vars );
use Type::Utils            qw( enum );

extends q(Async::IPC::Base);

my $CODEC_TYPE = enum 'CODEC_TYPE' => [ 'Sereal', 'Storable' ];
my $MODE_TYPE  = enum 'MODE_TYPE'  => [ 'async', 'sync' ];

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

   substr( ${ $buf_ref }, 0, 4 + $len) = NUL;

   my $result = shift @{ $self->result_queue };

   $result and return $result->( $self, 'recv', $record );

   return $self->invoke_event( 'on_recv', $record );
};

my $_recv_async = sub {
   my ($self, %args) = @_;

   my $on_recv = $args{on_recv}; my $on_eof = $args{on_eof};

   push @{ $self->result_queue }, sub {
      my ($self, $type, $record) = @_;

      if    ($type eq 'recv') { $on_recv and $on_recv->( $self, $record ) }
      elsif ($type eq 'eof' ) { $on_eof  and $on_eof->( $self ) }
   };

   return TRUE;
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

   my $len  = syswrite $self->write_handle, $bytes, length $bytes; my $lead;

   if (defined $len) {
      $lead = log_leader 'debug', $self->name, $self->pid;
      $self->log->debug( $lead."Wrote ${len} bytes" );
   }
   else {
      $lead = log_leader 'error', $self->name, $self->pid;
      $self->log->error( $lead.$OS_ERROR );
   }

   return $len;
};

my $_build_stream = sub {
   my $self = shift; return Async::IPC::Stream->new
      (  autoflush    => TRUE,
         builder      => $self->_usul,
         description  => $self->description.' stream',
         loop         => $self->loop,
         name         => $self->name.'_stream',
         on_read      => $self->capture_weakself( $_on_stream_read ),
         read_handle  => $self->read_handle,
         write_handle => $self->write_handle, );
};

has '+autostart'   => default => FALSE;

has 'codec'        => is => 'ro',   isa => $CODEC_TYPE, default => 'Storable';

has 'decode'       => is => 'lazy', isa => CodeRef, builder => $_build_decode;

has 'encode'       => is => 'lazy', isa => CodeRef, builder => $_build_encode;

has 'on_eof'       => is => 'ro',   isa => Maybe[CodeRef];

has 'on_recv'      => is => 'ro',   isa => Maybe[CodeRef];

has 'pair'         => is => 'lazy', isa => ArrayRef,
   builder         => sub { nonblocking_write_pipe_pair() };

has 'read_handle'  => is => 'rwp',  isa => Maybe[FileHandle],
   builder         => sub { $_[ 0 ]->pair->[ 0 ] }, lazy => TRUE;

has 'read_mode'    => is => 'lazy', isa => $MODE_TYPE, default => 'sync';

has 'result_queue' => is => 'ro',   isa => ArrayRef, builder => sub { [] };

has 'stream'       => is => 'lazy', isa => Object,   builder => $_build_stream;

has 'write_handle' => is => 'rwp',  isa => Maybe[FileHandle],
   builder         => sub { $_[ 0 ]->pair->[ 1 ] }, lazy => TRUE;

has 'write_mode'   => is => 'ro',   isa => $MODE_TYPE, default => 'sync';

sub BUILD {
   my $self = shift; $self->read_handle; $self->write_handle;

   ($self->read_mode eq 'async' or $self->write_mode eq 'async')
      and $self->stream;
   return;
}

sub DEMOLISH {
   $_[ 0 ]->close; return;
}

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

sub start {
   my ($self, $dirn) = @_;

   if    ($dirn eq 'read' ) { $self->$_maybe_close_write_handle }
   elsif ($dirn eq 'write') { $self->$_maybe_close_read_handle  }
   else { throw 'A channel must start either read or write' }

   $self->_set_pid( $PID );
   return;
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

=item C<on_eof>

=item C<on_recv>

=item C<pair>

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
