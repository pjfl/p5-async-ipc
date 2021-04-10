package Async::IPC::Stream;

use namespace::autoclean;

use Async::IPC::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use Async::IPC::Functions qw( log_debug log_error throw );
use Async::IPC::Reader;
use Async::IPC::Writer;
use Async::IPC::Types     qw( ArrayRef Bool CodeRef DataEncoding Maybe
                              NonEmptySimpleStr NonZeroPositiveInt Object
                              PositiveInt ScalarRef Str );
use Encode 2.11           qw( find_encoding STOP_AT_PARTIAL );
use English               qw( -no_match_vars );
use Errno                 qw( EAGAIN EWOULDBLOCK EINTR EPIPE );
use Ref::Util             qw( is_coderef );
use Scalar::Util          qw( blessed );
use Unexpected::Functions qw( Unspecified );
use Moo;

extends q(Async::IPC::Handle);

# Public attributes
has 'at_read_high_watermark'    => is => 'rwp',  isa => Bool, default => FALSE;

has 'autoflush'                 => is => 'ro',   isa => Bool, default => FALSE;

has 'bytes_remaining'           => is => 'rwp',  isa => Str,  default => NUL;

has 'close_on_read_eof'         => is => 'ro',   isa => Bool, default => TRUE;

has 'encoder'                   => is => 'lazy', isa => Maybe[Object],
   builder                      => '_build_encoder';

has 'encoding'                  => is => 'ro',   isa => Maybe[DataEncoding];

has 'flushing_read'             => is => 'rwp',  isa => Bool, default => FALSE;

has 'on_outgoing_empty'         => is => 'ro',   isa => Maybe[CodeRef];

has 'on_read'                   => is => 'ro',   isa => Maybe[CodeRef];

has 'on_read_eof'               => is => 'ro',   isa => Maybe[CodeRef];

has 'on_read_error'             => is => 'ro',   isa => Maybe[CodeRef];

has 'on_read_high_watermark'    => is => 'ro',   isa => CodeRef,
   builder                      => sub {
      sub { $_[0]->want_readready_for_read(FALSE) } };

has 'on_read_low_watermark'     => is => 'ro',   isa => CodeRef,
   builder                      => sub {
      sub { $_[0]->want_readready_for_read(TRUE) } };

has '+on_read_ready'            => builder => \&_on_read_ready;

has 'on_write_eof'              => is => 'ro',   isa => Maybe[CodeRef];

has 'on_write_error'            => is => 'ro',   isa => Maybe[CodeRef];

has '+on_write_ready'           => builder => \&_on_write_ready;

has 'on_writeable_start'        => is => 'ro',   isa => Maybe[CodeRef];

has 'on_writeable_stop'         => is => 'ro',   isa => Maybe[CodeRef];

has 'read_all'                  => is => 'ro',   isa => Bool, default => FALSE;

has 'read_eof'                  => is => 'rwp',  isa => Bool, default => FALSE;

has 'read_high_watermark'       => is => 'ro',   isa => PositiveInt,
   default                      => 0;

has 'read_low_watermark'        => is => 'ro',   isa => PositiveInt,
   default                      => 0;

has 'read_len'                  => is => 'ro',   isa => NonZeroPositiveInt,
   default                      => 8_192;

has 'readbuff'                  => is => 'rwp',  isa => ScalarRef,
   builder                      => sub { my $v = NUL; return \$v };

has 'reader'                    => is => 'ro',   isa => CodeRef,
   builder                      => '_build_reader';

has 'readqueue'                 => is => 'ro',   isa => ArrayRef,
   builder                      => sub { [] };

has 'stream_closing'            => is => 'rwp',  isa => Bool, default => FALSE;

has 'want_readready_for_read'   => is => 'rw',   isa => Bool, default => TRUE,
   lazy                         => TRUE, trigger => \&_toggle_read_watcher;

has 'want_readready_for_write'  => is => 'rw',   isa => Bool, default => FALSE,
   lazy                         => TRUE, trigger => \&_toggle_read_watcher;

has 'want_writeready_for_read'  => is => 'rw',   isa => Bool, default => FALSE,
   lazy                         => TRUE, trigger => \&_toggle_write_watcher;

has 'want_writeready_for_write' => is => 'rw',   isa => Bool, default => FALSE,
   lazy                         => TRUE, trigger => \&_toggle_write_watcher;

has 'writeable'                 => is => 'rwp',  isa => Bool, default => TRUE;

has 'write_all'                 => is => 'ro',   isa => Bool, default => FALSE;

has 'write_eof'                 => is => 'rwp',  isa => Bool, default => FALSE;

has 'write_len'                 => is => 'ro',   isa => NonZeroPositiveInt,
   default                      => 8_192;

has 'writequeue'                => is => 'ro',   isa => ArrayRef,
   builder                      => sub { [] };

has 'writer'                    => is => 'ro',   isa => CodeRef,
   builder                      => '_build_writer';

# Construction
sub BUILD {
   my $self = shift;

   throw Unspecified, ['on_read']
      if defined $self->read_handle and not $self->on_read;

   return;
}

before 'start' => sub {
   my $self = shift;

   $self->want_writeready_for_write(TRUE) unless $self->_is_empty;

   return;
};

# Public methods
sub close {
   my $self = shift;

   return $self->close_when_empty;
}

sub close_now {
   my $self = shift;

   for my $writer (@{$self->writequeue}) {
      $writer->on_error->('stream closing') if $writer->on_error;
   }

   splice @{$self->writequeue};
   $self->_set_stream_closing(FALSE);

   return $self->SUPER::close;
}

sub close_when_empty {
   my $self = shift;

   return $self->SUPER::close if $self->_is_empty;

   $self->_set_stream_closing(TRUE);

   return FALSE;
}

sub read_atmost {
   my ($self, $len) = @_;

   my $f = $self->_read_future;

   $self->_push_on_read(sub {
      my (undef, $buffref, $eof) = @_;

      return if $f->is_cancelled;

      $f->done(substr(${$buffref}, 0, $len, NUL), $eof);

      return;
   }, future => $f);

   return $f;
}

sub read_exactly {
   my ($self, $len) = @_;

   my $f = $self->_read_future;

   $self->_push_on_read(sub {
      my (undef, $buffref, $eof) = @_;

      return if $f->is_cancelled;

      return FALSE unless $eof || length ${$buffref} >= $len;

      $f->done(substr(${$buffref}, 0, $len, NUL), $eof);

      return;
   }, future => $f);

   return $f;
}

sub read_until {
   my ($self, $until) = @_;

   my $f = $self->_read_future;

   $until = qr{ \Q$until\E }mx unless ref $until;

   $self->_push_on_read(sub {
      my (undef, $buffref, $eof) = @_;

      return if $f->is_cancelled;

      if (${$buffref} =~ $until) {
         $f->done(substr(${$buffref}, 0, $+[0], NUL), $eof);
         return;
      }
      elsif ($eof) {
         $f->done(${$buffref}, $eof);
         ${$buffref} = NUL;
         return;
      }

      return FALSE;
   }, future => $f);

   return $f;
}

sub read_until_eof {
   my $self = shift;
   my $f    = $self->_read_future;

   $self->_push_on_read(sub {
      my (undef, $buffref, $eof) = @_;

      return if $f->is_cancelled;

      return FALSE unless $eof;

      $f->done(${$buffref}, $eof);
      ${$buffref} = NUL;

      return;
   }, future => $f);

   return $f;
}

sub write {
   my ($self, $data, %params) = @_;

   if ($self->stream_closing) {
      log_error $self, 'Cannot write to a closing stream';
      return;
   }

   my $handle = $self->write_handle;

   unless (defined $handle) {
      log_error $self, "Stream: Attribute 'write_handle' undefined";
      return;
   }

   if (my $encoder = $self->encoder) {
      $data = $encoder->encode($data) unless ref $data;
   }

   my $on_write = delete $params{on_write};
   my $on_flush = delete $params{on_flush};
   my $on_error = delete $params{on_error};
   my $len      = delete $params{write_len} // $self->write_len;

   throw 'Write method unrecognised keys - '.(join ', ', keys %params)
      if keys %params;

   my $f;

   if (defined wantarray) {
      my $orig_on_flush = $on_flush;
      my $orig_on_error = $on_error;

      $f = $self->factory->new_future;

      $on_flush = sub {
         $f->done; $orig_on_flush->(@_) if $orig_on_flush;
      };

      $on_error = sub {
         my ($self, $errno, @args) = @_;

         $f->fail("Write failed: ${errno}", 'syswrite', $errno)
            unless $f->is_ready;

         $orig_on_error->($self, $errno, @args) if $orig_on_error;
      };
   }

   push @{$self->writequeue}, Async::IPC::Writer->new(
      $data, $len, $on_write, $on_flush, $on_error, FALSE
   );

   if ($self->autoflush) {
      1 while (!$self->_is_empty and $self->_flush_one_write);

      if ($self->_is_empty) {
         $self->want_writeready_for_write(FALSE);
         return $f;
      }
   }

   $self->want_writeready_for_write(TRUE);
   return $f;
}

# Private functions
sub _nonfatal_error {
   my $errno = shift;

   return $errno == EAGAIN || $errno == EWOULDBLOCK || $errno == EINTR;
}

sub _reduce_queue {
   my $queue = shift;
   my $head  = $queue->[0];
   my $second;

   while ($second = $queue->[1]
          and !ref $second->data
          and $head->writelen == $second->writelen
          and !$head->on_write
          and !$second->on_write
          and !$head->on_flush) {
      $head->data    .= $second->data;
      $head->on_write = $second->on_write;
      $head->on_flush = $second->on_flush;
      splice @{$queue}, 1, 1, ();
   }

   return;
}

# Private methods
sub _build_encoder {
   my $self = shift;

   return unless $self->encoding;

   my $encoder = find_encoding($self->encoding);

   throw 'Encoding [_1] unknown', [$self->encoding] unless $encoder;

   return $encoder;
}

sub _build_reader {
   return sub {
      my ($self, $handle, undef, $len) = @_;

      return sysread $handle, $_[2], $len;
   }
}

sub _build_writer {
   return sub {
      my ($self, $handle, $data_ref, $len) = @_;

      my $wrote = syswrite $handle, ${$data_ref}, $len;

      ${$data_ref} = substr(${$data_ref}, $wrote) if $wrote;

      return $wrote;
   }
}

sub _handle_read_error {
   my ($self, $errno) = @_;

   return if _nonfatal_error($errno);

   $self->close_now unless $self->maybe_invoke_event('on_read_error', $errno);

   for (grep { $_->future } @{$self->{readqueue}}) {
      $_->future->fail("Read failed: ${errno}", 'sysread', $errno);
   }

   splice @{$self->readqueue};
   return;
}

sub _handle_write_error {
   my ($self, $head, $errno) = @_;

   if ($errno == EAGAIN or $errno == EWOULDBLOCK) {
      $self->maybe_invoke_event('on_writeable_stop') if $self->writeable;
      $self->_set_writeable(FALSE);
   }

   return FALSE if _nonfatal_error($errno);

   if ($errno == EPIPE) {
      $self->_set_write_eof(TRUE);
      $self->maybe_invoke_event('on_write_eof');
   }

   $head->on_error->($self, $errno) if $head->on_error;

   $self->close_now unless $self->maybe_invoke_event('on_write_error', $errno);

   return FALSE;
}

sub _is_empty {
   my $self = shift;

   return !@{$self->writequeue // []};
}

sub _toggle_read_watcher {
   my ($self, $want) = @_;

   return unless defined $want;

   $self->want_readready(
      $self->want_readready_for_read || $self->want_readready_for_write
   ) if $self->read_handle;

   return;
}

sub _toggle_write_watcher {
   my ($self, $want) = @_;

   return unless defined $want;

   $self->want_writeready(
      $self->want_writeready_for_read || $self->want_writeready_for_write
   ) if $self->write_handle;

   return;
}

sub _flush_one_read {
   my ($self, $eof) = @_;

   $eof //= FALSE;
   $self->_set_flushing_read(TRUE);

   my $readqueue = $self->readqueue;
   my $ret;

   if ($readqueue->[0] and my $on_read = $readqueue->[0]->on_read) {
      $ret = $on_read->($self, $self->readbuff, $eof);
   }
   else { $ret = $self->invoke_event('on_read', $self->readbuff, $eof) }

   my $len = length ${$self->readbuff};

   if ($self->read_low_watermark
       and $self->at_read_high_watermark
       and $len < $self->read_low_watermark) {
      $self->_set_at_read_high_watermark(FALSE);
      $self->invoke_event('on_read_low_watermark', $len);
   }

   if (is_coderef $ret) { # Replace the top CODE, or add it if there was none
      $readqueue->[0] = Async::IPC::Reader->new($ret, undef);
      $ret = TRUE;
   }
   elsif (@{$readqueue} and not defined $ret) {
      shift @{$readqueue};
      $ret = TRUE;
   }
   else {
      $ret = $ret && (($len > 0) || $eof);
      $ret //= FALSE;
   }

   log_debug $self, "Flush one read: EOF ${eof} RET ${ret} LEN ${len}";
   $self->_set_flushing_read(FALSE);
   return $ret;
}

sub _flush_one_write {
   my $self       = shift;
   my $writequeue = $self->writequeue;
   my $head;

   while ($head = $writequeue->[0] and ref $head->data) {
      if (is_coderef $head->data) {
         my $data = $head->data->($self);

         unless (defined $data) {
            $head->on_flush->($self) if $head->on_flush;
            shift @{$writequeue};
            return TRUE;
         }

         if (my $encoder = $self->encoder) {
            $data = $encoder->encode($data) unless ref $data;
         }

         unshift @{$writequeue}, Async::IPC::Writer->new(
            $data, $head->writelen, $head->on_write, undef, undef, FALSE
         );
      }
      elsif (blessed $head->data and $head->data->isa('Future')) {
         my $f = $head->data;

         unless ($f->is_ready) {
            return FALSE if $head->watching;

            $f->on_ready(sub { $self->_flush_one_write });
            $head->watching(TRUE);
            return FALSE;
         }

         my $data = $f->get;

         if (my $encoder = $self->encoder) {
            $data = $encoder->encode($data) unless ref $data;
         }

         $head->data = $data;
      }
      else { throw 'Reference [_1] unknown to write queue', [$head->data] }
   }

   _reduce_queue($writequeue);

   throw 'TODO: head data does not contain a plain string' if ref $head->data;

   my $wrote = $self->writer->(
      $self, $self->write_handle, \$head->data, $head->writelen
   );

   return $self->_handle_write_error($head, $ERRNO) unless defined $wrote;

   log_debug $self, "Wrote ${wrote} bytes. Head length ".(length $head->data);

   $head->on_write->($self, $wrote) if $head->on_write;

   unless (length $head->data) {
      $head->on_flush->($self) if $head->on_flush;

      shift @{$self->writequeue};
   }

   return TRUE;
}

sub _do_read {
   my $self   = shift;
   my $handle = $self->read_handle;

   while (TRUE) {
      my $data;
      my $red = $self->reader->($self, $handle, $data, $self->read_len);

      log_debug $self, 'Read '.($red // 'undef').' bytes';

      return $self->_handle_read_error($ERRNO) unless defined $red;

      $self->_set_read_eof(my $eof = ($red == 0));

      if (my $encoder = $self->encoder) {
         my $bytes = (length $self->bytes_remaining)
                   ? $self->bytes_remaining.$data : $data;

         $data = $encoder->decode($bytes, STOP_AT_PARTIAL);
         $self->_set_bytes_remaining($bytes);
      }

      unless ($eof) {
         $self->_set_readbuff(do { my $v = ${ $self->readbuff }.$data; \$v });
      }

      1 while ($self->_flush_one_read($eof));

      if ($eof) {
         $self->maybe_invoke_event('on_read_eof');

         $self->close_now if $self->close_on_read_eof;

         for (grep { $_->future } @{$self->{readqueue}}) {
            $_->future->done(undef);
         }

         splice @{$self->readqueue};
         return;
      }

      last unless $self->read_all;
   }

   my $len = length ${$self->readbuff};

   if ($self->read_high_watermark and $len >= $self->read_high_watermark) {
      $self->invoke_event('on_read_high_watermark', $len)
         unless $self->at_read_high_watermark;

      $self->_set_at_read_high_watermark(TRUE);
   }

   return;
}

sub _do_write {
   my $self      = shift;
   my $write_all = $self->write_all;

   1 while (!$self->_is_empty && $self->_flush_one_write && $write_all);

   if ($self->_is_empty) { # All data successfully flushed
      $self->want_writeready_for_write(FALSE);
      $self->maybe_invoke_event('on_outgoing_empty');

      $self->close_now if $self->stream_closing;
   }

   return;
}

sub _on_read_ready {
   my $self = shift;

   return
      unless $self->want_readready_for_read || $self->want_readready_for_write;

   return sub {
      my $self = shift;

      $self->_do_read if $self->want_readready_for_read;
      $self->_do_write if $self->want_readready_for_write;
      return;
   };
}

sub _on_write_ready {
   my $self = shift;

   return unless $self->want_writeready;

   return sub {
      my $self = shift;

      unless ($self->writeable) {
         $self->maybe_invoke_event('on_writeable_start');
         $self->_set_writeable(TRUE);
      }

      $self->_do_read if $self->want_writeready_for_read;
      $self->_do_write if $self->want_writeready_for_write;
      return;
   };
}

sub _push_on_read {
   my ($self, $on_read, %args) = @_; # %args undocumented for internal use

   push @{$self->readqueue}, Async::IPC::Reader->new($on_read, $args{future});

   # TODO: Should this always defer?
   return if $self->flushing_read;

   1 while (length ${$self->readbuff} and $self->_flush_one_read);

   return;
}

sub _read_future {
   my $self = shift;
   my $f    = $self->factory->new_future;

   $f->on_cancel($self->capture_weakself(sub {
      my $self = shift or return; 1 while $self->_flush_one_read;
   }));

   return $f;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Stream - Asyncronous inter process communication

=head1 Synopsis

   use Async::IPC::Stream;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<at_read_high_watermark>

=item C<autoflush>

=item C<bytes_remaining>

=item C<close_on_read_eof>

=item C<encoding>

=item C<flushing_read>

=item C<on_outgoing_empty>

=item C<on_read>

=item C<on_read_eof>

=item C<on_read_error>

=item C<on_read_high_watermark>

=item C<on_read_low_watermark>

=item C<on_read_ready>

=item C<on_write_eof>

=item C<on_write_error>

=item C<on_write_ready>

=item C<on_writeable_start>

=item C<on_writeable_stop>

=item C<read_all>

=item C<read_eof>

=item C<read_high_watermark>

=item C<read_len>

=item C<read_low_watermark>

=item C<readbuff>

=item C<reader>

=item C<readqueue>

=item C<start>

=item C<stream_closing>

=item C<writeable>

=item C<write_all>

=item C<write_eof>

=item C<write_len>

=item C<writequeue>

=item C<writer>

=back

=head1 Subroutines/Methods

=head2 C<BUILD>


=head2 C<close>

=head2 C<close_now>

=head2 C<close_when_empty>

=head2 C<read_atmost>

=head2 C<read_exactly>

=head2 C<read_until>

=head2 C<read_until_eof>

=head2 C<write>

=head1 Diagnostics

None

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
