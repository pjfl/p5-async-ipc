package Async::IPC::FileStream;

use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_debug );
use Class::Usul::Constants qw( FALSE NUL TRUE );
use Class::Usul::Functions qw( throw );
use Class::Usul::Types     qw( Bool CodeRef HashRef Maybe Object PositiveInt );
use Fcntl                  qw( :seek );
use Scalar::Util           qw( blessed );

extends qw(Async::IPC::Stream);

my $_build_file = sub {
   my $self = shift; return $self->factory->new_notifier
      ( type              => 'file',
        description       => $self->description.' file',
        name              => $self->name.'_file',
        on_devino_changed => $self->replace_weakself( 'on_devino_changed' ),
        on_size_changed   => $self->replace_weakself( 'on_size_changed' ),
        %{ $self->file_attr }, );
};

my $_build_on_devino_changed = sub {
   return sub {
      my $self = shift or return; log_debug $self, 'Device inode changed';

      $self->_set_renamed( TRUE ); $self->read_more;

      return;
   };
};

my $_build_on_size_changed = sub {
   return sub {
      my $self = shift or return; my ($old_size, $new_size) = @_;

      if ($new_size < $self->last_size) {
         $self->maybe_invoke_event( 'on_truncated' ); $self->_set_last_pos( 0 );
      }

      log_debug $self, "File size ${new_size} bytes";
      $self->_set_last_size( $new_size );
      $self->read_more;
      return;
   };
};

my $_toggle_read_watcher = sub {
   my ($self, $want) = @_;

   if ($want) { $self->file->start } else { $self->file->stop }

   return;
};

my $_toggle_write_watcher = sub {
   my ($self, $want) = @_;

   $want and throw 'Class [_1] cannot watch write', [ blessed $self || $self ];

   return;
};

has '+close_on_read_eof' => default => FALSE;

has 'file'               => is => 'lazy', isa => Object,
   builder               => $_build_file;

has 'file_attr'          => is => 'ro',   isa => HashRef, builder => sub { {} };

has 'last_pos'           => is => 'rwp',  isa => Maybe[PositiveInt];

has 'last_size'          => is => 'rwp',  isa => Maybe[PositiveInt];

has 'on_devino_changed'  => is => 'ro',   isa => CodeRef,
   builder               => $_build_on_devino_changed;

has 'on_initial'         => is => 'ro',   isa => Maybe[CodeRef];

has 'on_size_changed'    => is => 'ro',   isa => CodeRef,
   builder               => $_build_on_size_changed;

has 'on_truncated'       => is => 'ro',   isa => Maybe[CodeRef];

has 'renamed'            => is => 'rwp',  isa => Bool, default => FALSE;

has 'running_initial'    => is => 'rwp',  isa => Bool, default => TRUE;

has '+want_readready'    => trigger => $_toggle_read_watcher;

has '+want_writeready'   => trigger => $_toggle_write_watcher;

around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   my $args = { autostart => FALSE };

   for my $k (qw( interval path )) {
      my $v = delete $attr->{ $k }; defined $v and $args->{ $k } = $v;
   }

   $args->{handle   } = $attr->{read_handle};
   $attr->{file_attr} = $args;
   return $attr;
};

sub BUILD {
   my $self = shift;

   $self->_set_last_size( my $size = $self->file->path->stat->{size} );
   $self->maybe_invoke_event( 'on_initial', $size );
   $self->_set_running_initial( FALSE );
   return;
}

sub read_more {
   my $self = shift; my $path = $self->file->path;

   defined $self->last_pos and $path->seek( $self->last_pos, SEEK_SET );

   $self->invoke_event( 'on_read_ready' );
   $self->_set_last_pos( $path->tell );

   if ($self->last_pos < $self->last_size) {
      $self->loop->watch_idle( $self->pid, sub { $self->read_more } );
   }
   elsif ($self->renamed) {
      $self->_set_last_size( 0 ); log_debug $self, 'Reopening for rename';

      if ($self->last_pos) {
         $self->maybe_invoke_event( 'on_truncated' );
         $self->_set_last_pos( 0 );
         $self->loop->watch_idle( $self->pid, sub { $self->read_more } );
      }

      $path->close; $path->assert_open; $self->_set_renamed( FALSE );
   }

   return;
}

sub seek {
   my ($self, $offset, $whence) = @_; my $path = $self->file->path;

   $self->running_initial or throw 'Cannot seek except during on_initial';

   $path->seek( $offset, $whence // SEEK_SET );
   return;
}

sub seek_to_last {
   my ($self, $str_pattern, %opts) = @_;

   $self->running_initial
      or throw 'Cannot seek_to_last except during on_initial';

   my $offset  = $self->last_size; my $blocksize = $opts{blocksize} // 8_192;

   defined $opts{horizon} or $opts{horizon} = 4 * $blocksize;

   my $horizon = $opts{horizon} ? $offset - $opts{horizon} : 0;

   $horizon < 0 and $horizon = 0;

   my $prev = NUL; my $path = $self->file->path->block_size( $blocksize );

   my $re   = ref $str_pattern ? $str_pattern : qr{ \Q$str_pattern\E }mx;

   while ($offset > $horizon) {
      my $len = $blocksize;

      $len > $offset and $len = $offset; $offset -= $len;

      $path->clear->seek( $offset, SEEK_SET )->read;

      # TODO: If $str_pattern is a plain string this could be more efficient
      # using rindex
      if (() = (${ $path->buffer }.$prev) =~ m{ $re }gmsx ) {
         # $+[0] will be end of last match
         my $pos = $offset + $+[ 0 ]; $self->seek( $pos ); return TRUE;
      }

      $prev = ${ $path->buffer };
   }

   $self->seek( $horizon );
   return FALSE;
}

sub write {
   throw 'Class [_1] cannot call write method', [ blessed $_[ 0 ] || $_[ 0 ] ];
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::FileStream - Asyncronous inter process communication

=head1 Synopsis

   use Async::IPC::FileStream;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<close_on_read_eof>

=item C<file>

=item C<file_attr>

=item C<last_pos>

=item C<last_size>

=item C<on_devino_changed>

=item C<on_initial>

=item C<on_size_changed>

=item C<on_truncated>

=item C<renamed>

=item C<running_initial>

=item C<+want_readready>

=item C<+want_writeready>

=back

=head1 Subroutines/Methods

=head2 C<BUILDARGS>

=head2 C<BUILD>

=head2 C<read_more>

=head2 C<seek>

=head2 C<seek_to_last>

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
