package Async::IPC::File;

use namespace::autoclean;

use Moo;
use Class::Usul::Constants     qw( TRUE );
use File::DataClass::Constants qw( STAT_FIELDS );
use File::DataClass::IO        qw( io );
use File::DataClass::Types     qw( ArrayRef HashRef Maybe Path );
use Scalar::Util               qw( blessed );

extends q(Async::IPC::Periodical);

has '+interval' => default => 2;

has 'events'    => is => 'ro', isa => HashRef, builder => sub { {} };

has 'last_stat' => is => 'rw', isa => Maybe[HashRef];

has 'path'      => is => 'ro', isa => Path, required => TRUE;

my $_stat_fields = sub {
   return [ grep { $_ ne 'blksize' && $_ ne 'blocks' } STAT_FIELDS ];
};

my $_maybe_invoke_event = sub {
   my ($self, $ev_name, $old, $new) = @_;

   exists $self->events->{ $ev_name }
      and $self->events->{ $ev_name }->( $self, $old, $new );

   return;
};

my $_call_handler = sub {
   return sub {
      my $self = shift; my $old = $self->last_stat;

      not defined $old and not $self->path->exists and return;

      if (defined $old and not $self->path->exists) { # Path deleted
         $self->$_maybe_invoke_event( 'on_stat_changed', $old );
         $self->last_stat( undef );
         return;
      }

      my $new  = $self->path->stat;

      unless (defined $old) { # Watch for the path to be created
         $self->$_maybe_invoke_event( 'on_stat_changed', undef, $new );
         $self->last_stat( $new );
         return;
      }

      my $any_change;

      if ($old->{device} != $new->{device} or $old->{inode} != $new->{inode}) {
         $self->$_maybe_invoke_event( 'on_devino_changed', $old, $new );
         $any_change++;
      }

      for my $stat (@{ $_stat_fields->() }) {
         $old->{ $stat } == $new->{ $stat } and next; $any_change++;

         $self->$_maybe_invoke_event
            ( "on_${stat}_changed", $old->{ $stat }, $new->{ $stat } );
      }

      if ($any_change) {
         $self->$_maybe_invoke_event( 'on_stat_changed', $old, $new );
         $self->last_stat( $new );
      }

      return;
   };
};

around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   for my $stat ('devino', @{ $_stat_fields->() }, 'stat') {
      my $ev = delete $attr->{ "on_${stat}_changed" };

      $attr->{events}->{ "on_${stat}_changed" } //= $ev;
   }

   my $path; ($path = $attr->{path} and blessed $path
      and $path->isa( 'File::DataClass::IO' ))
      or  $attr->{path} = $path ? io $path : $path;

   $attr->{last_stat} = ($attr->{path} && $attr->{path}->exists)
                      ?  $attr->{path}->stat : undef;
   $attr->{code     } = $_call_handler->();
   return $attr;
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

=item C<last_stat>

=item C<path>

=back

=head1 Subroutines/Methods

=head2 BUILDARGS

=head2 BUILD

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
