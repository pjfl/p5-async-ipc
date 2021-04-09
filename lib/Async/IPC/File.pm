package Async::IPC::File;

use namespace::autoclean;

use Async::IPC::Constants      qw( FALSE TRUE );
use Async::IPC::Functions      qw( log_debug throw );
use English                    qw( -no_match_vars );
use File::DataClass::Constants qw( STAT_FIELDS );
use File::DataClass::IO        qw( io );
use File::DataClass::Types     qw( ArrayRef HashRef Maybe Object Path );
use Module::Load::Conditional  qw( can_load );
use Scalar::Util               qw( blessed );
use Moo;

extends q(Async::IPC::Periodical);

# Public attributes
has 'events'      => is => 'ro',   isa => HashRef, builder => sub { {} };

has '+interval'   => default => 2;

has 'last_stat'   => is => 'rwp',  isa => Maybe[HashRef];

has 'path'        => is => 'ro',   isa => Path, required => TRUE;

# Private attributes
has '_fsnotifier' =>
   is       => 'lazy',
   isa      => Maybe[Object],
   builder  => '_build_fsnotifier',
   init_arg => undef,
   reader   => 'fsnotifier';

has '_watchers' =>
   is       => 'lazy',
   isa      => Maybe[ArrayRef],
   builder  => '_build_watchers',
   init_arg => undef,
   reader   => 'watchers';

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_;

   my $attr = $orig->($self, @args);

   for my $field ('devino', _stat_fields(), 'stat') {
      my $code = delete $attr->{"on_${field}_changed"};

      $attr->{events}->{"on_${field}_changed"} //= $code if defined $code;
   }

   my $path = $attr->{path};

   $attr->{path} = $path ? io $path : $path
      unless $path && blessed $path && $path->isa('File::DataClass::IO');

   if (my $handle = delete $attr->{handle}) {
      $handle = IO::Handle->new_from_fd($handle, 'r') unless blessed $handle;
      $attr->{path} = io { io_handle => $handle };
   }

   if ($path = $attr->{path}) { $attr->{last_stat} = $path->stat }

   $attr->{code} = \&_call_handler;
   return $attr;
};

around 'start' => sub {
   my ($orig, $self, @args) = @_;

   if (my $notifier = $self->fsnotifier and $self->watchers) {

      log_debug $self, 'Starting '.$self->description.' native';

      my $cb = sub { $notifier->poll };

      return $self->loop->watch_read_handle($notifier->fileno, $cb);
   }

   return $orig->($self, @args);
};

around 'stop' => sub {
   my ($orig, $self, @args) = @_;

   if (my $notifier = $self->fsnotifier and my $watchers = $self->watchers) {
      log_debug $self, 'Stopping '.$self->description.' native';
      $self->loop->unwatch_read_handle($notifier->fileno);
      $watchers->[0]->cancel;
      $watchers->[1]->cancel if $watchers->[1];
      return;
   }

   return $orig->($self, @args);
};

# Private methods
sub _build_fsnotifier {
   my $notifier;
   my $modules = { 'Linux::Inotify2' => '1.22' };

   if ($OSNAME eq 'linux' && can_load(modules => $modules)) {
      throw 'Inotify2 object cannot create: [_1]', [$ERRNO]
         unless $notifier = Linux::Inotify2->new;
   }

   return $notifier;
}

sub _build_watchers {
   my $self     = shift;
   my $notifier = $self->fsnotifier or return;
   my $path     = $self->path; $path->name or return;
   my $dmask    = Linux::Inotify2::IN_CREATE();
   my $cb       = $self->capture_weakself(sub {
      my ($self, $ev) = @_;

      $self->code->($self, $ev) if $ev->fullname eq $path;

      return;
   } );
   my $dwatch   = $notifier->watch($path->dirname, $dmask, $cb)
      or throw 'Watcher object cannot create: [_1]', [$ERRNO];
   my $fwatch;

   $fwatch = $self->_create_file_watcher if $path->exists;

   return [$dwatch, $fwatch];
}

sub _call_handler {
   my ($self, $ev) = @_;

   my $path = $self->path;
   my $old  = $self->last_stat;
   my $new  = $path->stat;

   return if !defined $old && !defined $new;

   if (defined $old && !defined $new) { # Path deleted
      log_debug $self, "Path ${path} deleted";
      $self->_maybe_invoke_event('on_stat_changed', $old);
      $self->_set_last_stat(undef);

      if ($ev && $self->watchers && $self->watchers->[1]) {
         $self->watchers->[1]->cancel;
         delete $self->watchers->[1];
      }

      return;
   }

   unless (defined $old) { # Watch for the path to be created
      log_debug $self, "Path ${path} found";
      $self->_maybe_invoke_event('on_stat_changed', undef, $new);
      $self->_set_last_stat($new);

      $self->watchers->[1] = $self->_create_file_watcher
         if $ev && $self->watchers && !$self->watchers->[1];

      return;
   }

   my $any_change = FALSE;

   if ($old->{device} != $new->{device} || $old->{inode} != $new->{inode}) {
      $self->_maybe_invoke_event('on_devino_changed', $old, $new);
      $any_change++;
   }

   for my $field (_stat_fields()) {
      next if $old->{$field} == $new->{$field};

      $any_change++;

      $self->_maybe_invoke_event(
         "on_${field}_changed", $old->{$field}, $new->{$field}
      );
   }

   if ($any_change) {
      $self->_maybe_invoke_event('on_stat_changed', $old, $new);
      $self->_set_last_stat($new);
   }

   if (defined $ev && blessed $ev && $ev->can('mask')) {
      log_debug $self, 'Called event '.$ev->mask." change ${any_change}";
   }
   else { log_debug $self, "Called change ${any_change}" }

   return;
}

sub _create_file_watcher {
   my $self    = shift;
   my $mask    = Linux::Inotify2::IN_ATTRIB()
               | Linux::Inotify2::IN_DELETE_SELF()
               | Linux::Inotify2::IN_MODIFY()
               | Linux::Inotify2::IN_MOVE_SELF();
   my $cb      = $self->capture_weakself($self->code);
   my $watcher = $self->fsnotifier->watch($self->path->name, $mask, $cb)
      or throw 'Watcher object cannot create: [_1]', [$ERRNO];

   return $watcher;
}

sub _maybe_invoke_event {
   my ($self, $ev_name, $old, $new) = @_;

   my $events = $self->events;

   $events->{$ev_name}->($self, $old, $new)
      if exists $events->{$ev_name} && defined $events->{$ev_name};

   return;
}

# Private functions
sub _stat_fields {
   return grep { $_ ne 'blksize' && $_ ne 'blocks' } STAT_FIELDS;
}

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
