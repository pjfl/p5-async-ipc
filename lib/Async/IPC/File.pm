package Async::IPC::File;

use namespace::autoclean;

use Async::IPC::Functions      qw( log_debug );
use Class::Usul::Constants     qw( FALSE TRUE );
use Class::Usul::Functions     qw( throw );
use English                    qw( -no_match_vars );
use File::DataClass::Constants qw( STAT_FIELDS );
use File::DataClass::IO        qw( io );
use File::DataClass::Types     qw( ArrayRef HashRef Maybe Object Path );
use Module::Load::Conditional  qw( can_load );
use Scalar::Util               qw( blessed );
use Moo;

extends q(Async::IPC::Periodical);

# Private attribute builders
my $_build_fsnotifier = sub {
   my $notifier; $OSNAME eq 'linux'
      and can_load( modules => { 'Linux::Inotify2' => '1.22' } )
      and $notifier = Linux::Inotify2->new
      or  throw 'Inotify2 object cannot create: [_1]', [ $ERRNO ];

   return $notifier;
};

my $_create_file_watcher = sub {
   my $self    = shift;
   my $mask    = Linux::Inotify2::IN_ATTRIB()
               | Linux::Inotify2::IN_DELETE_SELF()
               | Linux::Inotify2::IN_MODIFY()
               | Linux::Inotify2::IN_MOVE_SELF();
   my $cb      = $self->capture_weakself( $self->code );
   my $watcher = $self->fsnotifier->watch( $self->path->name, $mask, $cb )
      or throw 'Watcher object cannot create: [_1]', [ $ERRNO ];

   return $watcher;
};

my $_build_watchers = sub {
   my $self     = shift;
   my $notifier = $self->fsnotifier or return;
   my $path     = $self->path; $path->name or return;
   my $dmask    = Linux::Inotify2::IN_CREATE();
   my $cb       = $self->capture_weakself( sub {
      my ($self, $ev) = @_;

      $ev->fullname eq $path and $self->code->( $self, $ev );

      return;
   } );
   my $dwatch   = $notifier->watch( $path->dirname, $dmask, $cb )
      or throw 'Watcher object cannot create: [_1]', [ $ERRNO ];
   my $fwatch; $path->exists and $fwatch = $self->$_create_file_watcher;

   return [ $dwatch, $fwatch ];
};

# Public attributes
has 'events'      => is => 'ro',   isa => HashRef, builder => sub { {} };

has '+interval'   => default => 2;

has 'last_stat'   => is => 'rwp',  isa => Maybe[HashRef];

has 'path'        => is => 'ro',   isa => Path, required => TRUE;

# Private attributes
has '_fsnotifier' => is => 'lazy', isa => Maybe[Object],
   builder        => $_build_fsnotifier, init_arg => undef,
   reader         => 'fsnotifier';

has '_watchers'   => is => 'lazy', isa => Maybe[ArrayRef],
   builder        => $_build_watchers, init_arg => undef, reader => 'watchers';

# Private functions
my $_stat_fields = sub {
   return [ grep { $_ ne 'blksize' && $_ ne 'blocks' } STAT_FIELDS ];
};

# Private methods
my $_maybe_invoke_event = sub {
   my ($self, $ev_name, $old, $new) = @_; my $events = $self->events;

   exists $events->{ $ev_name } and defined $events->{ $ev_name }
      and $events->{ $ev_name }->( $self, $old, $new );

   return;
};

my $_call_handler = sub {
   my ($self, $ev) = @_; my $path = $self->path;

   my $old = $self->last_stat; my $new = $path->stat;

   not defined $old and not defined $new and return;

   if (defined $old and not defined $new) { # Path deleted
      log_debug $self, "Path ${path} deleted";
      $self->$_maybe_invoke_event( 'on_stat_changed', $old );
      $self->_set_last_stat( undef );

      if ($ev and $self->watchers and $self->watchers->[ 1 ]) {
         $self->watchers->[ 1 ]->cancel; delete $self->watchers->[ 1 ];
      }

      return;
   }

   unless (defined $old) { # Watch for the path to be created
      log_debug $self, "Path ${path} found";
      $self->$_maybe_invoke_event( 'on_stat_changed', undef, $new );
      $self->_set_last_stat( $new );
      $ev and $self->watchers and not $self->watchers->[ 1 ]
          and $self->watchers->[ 1 ] = $self->$_create_file_watcher;
      return;
   }

   my $any_change = FALSE;

   if ($old->{device} != $new->{device} or $old->{inode} != $new->{inode}) {
      $self->$_maybe_invoke_event( 'on_devino_changed', $old, $new );
      $any_change++;
   }

   for my $field (@{ $_stat_fields->() }) {
      $old->{ $field } == $new->{ $field } and next; $any_change++;

      $self->$_maybe_invoke_event
         ( "on_${field}_changed", $old->{ $field }, $new->{ $field } );
   }

   if ($any_change) {
      $self->$_maybe_invoke_event( 'on_stat_changed', $old, $new );
      $self->_set_last_stat( $new );
   }

   if (defined $ev and blessed $ev and $ev->can( 'mask' )) {
      log_debug $self, 'Called event '.$ev->mask." change ${any_change}";
   }
   else { log_debug $self, "Called change ${any_change}" }

   return;
};

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   for my $field ('devino', @{ $_stat_fields->() }, 'stat') {
      my $code = delete $attr->{ "on_${field}_changed" };

      defined $code and $attr->{events}->{ "on_${field}_changed" } //= $code;
   }

   my $path; ($path = $attr->{path} and blessed $path
      and $path->isa( 'File::DataClass::IO' ))
      or  $attr->{path} = $path ? io $path : $path;

   if (my $handle = delete $attr->{handle}) {
      blessed $handle or $handle = IO::Handle->new_from_fd( $handle, 'r' );
      $attr->{path} = io { io_handle => $handle };
   }

   $path = $attr->{path} and $attr->{last_stat} = $path->stat;
   $attr->{code} = $_call_handler;
   return $attr;
};

around 'start' => sub {
   my ($orig, $self, @args) = @_;

   my $notifier; $notifier = $self->fsnotifier and $self->watchers
      and log_debug( $self, 'Starting '.$self->description.' native' )
      and return $self->loop->watch_read_handle
         ( $notifier->fileno, sub { $notifier->poll } );

   return $orig->( $self, @args );
};

around 'stop' => sub {
   my ($orig, $self, @args) = @_;

   if (my $notifier = $self->fsnotifier and my $watchers = $self->watchers) {
      log_debug $self, 'Stopping '.$self->description.' native';
      $self->loop->unwatch_read_handle( $notifier->fileno );
      $watchers->[ 0 ]->cancel; $watchers->[ 1 ] and $watchers->[ 1 ]->cancel;
      return;
   }

   return $orig->( $self, @args );
};

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::File - Watch a file for changes

=head1 Synopsis

   use Async::IPC;

   my $factory = Async::IPC->new( builder => Class::Usul->new );

   my $file_watcher = $factory->new_notifier
      (  on_stat_changed => sub { ... code to run when file changes ... },
         desc            => 'description used by the logger',
         interval        => 3, # Optional polling innterval defaults to 2
         key             => 'logger key used to identify a log entry',
         path            => 'path to file',
         type            => 'file' );

=head1 Description

Periodically polls the file system to see if any changes have been made to
to specified file

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<events>

The supported event list is; C<device>, C<inode>, C<mode>, C<nlink>,
C<uid>, C<gid>, C<device_id>, C<size>, C<atime>, C<mtime>,  C<ctime>,
C<devino>, and C<stat>

=item C<interval>

Overrides the default, sets the time between polls of the file system to
two seconds

=item C<last_stat>

=item C<path>

=back

=head1 Subroutines/Methods

=head2 C<BUILDARGS>

=head2 C<BUILD>

=head2 C<start>

=head2 C<stop>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Async::IPC::Periodical>

=item L<Class::Usul::Types>

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
