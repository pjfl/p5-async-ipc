package Async::IPC::Routine;

use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader read_exactly recv_arg_error
                               send_msg terminate );
use Async::IPC::Process;
use Class::Usul::Constants qw( FALSE TRUE );
use Class::Usul::Functions qw( bson64id nonblocking_write_pipe_pair );
use Class::Usul::Types     qw( Bool HashRef Object );
use English                qw( -no_match_vars );
use Storable               qw( thaw );
use Try::Tiny;

extends q(Async::IPC::Base);

has 'child'      => is => 'lazy', isa => Object,  builder => sub {
   Async::IPC::Process->new( $_[ 0 ]->child_args ) };

has 'child_args' => is => 'lazy', isa => HashRef, default => sub { {} };

has 'is_running' => is => 'rwp',  isa => Bool,    default => TRUE;

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $args = $orig->( $self, @args ); my $attr;

   for my $k ( qw( builder description log_key ) ) {
      $attr->{ $k } = $args->{ $k };
   }

   for my $k ( qw( autostart ) ) {
      my $v = delete $args->{ $k }; defined $v and $attr->{ $k } = $v;
   }

   $args->{retn_pipe } = nonblocking_write_pipe_pair if ($args->{on_return});
   $args->{call_pipe } = nonblocking_write_pipe_pair;
   $args->{code      } = __call_handler( $args );
   $attr->{child_args} = $args;
   return $attr;
};

# Public methods
sub call {
   my ($self, @args) = @_; $self->is_running or return FALSE;

   $args[ 0 ] ||= bson64id; return $self->child->send( @args );
}

sub stop {
   my $self = shift; $self->_set_is_running( FALSE );

   my $pid  = $self->child->pid; $self->child->stop;

   $self->loop->watch_child( 0, sub { $pid } ); return;
}

# Private methods
sub _build_pid {
   return $_[ 0 ]->child->pid;
}

# Private functions
sub __call_handler {
   my $args   = shift;
   my $before = delete $args->{before};
   my $code   = delete $args->{code  };
   my $after  = delete $args->{after };
   my $rdr    = $args->{call_pipe} ? $args->{call_pipe}->[ 0 ] : FALSE;
   my $wtr    = $args->{retn_pipe} ? $args->{retn_pipe}->[ 1 ] : FALSE;

   return sub {
      my $self = shift; $before and $before->( $self );
      my $lead = log_leader 'error', 'EXCODE', $PID; my $log = $self->log;
      my $loop = $self->loop; my $max_calls = $self->max_calls; my $count = 0;

      $rdr and $loop->watch_read_handle( $rdr, sub {
         my $red = read_exactly $rdr, my $buf_len, 4;

         recv_arg_error $log, $PID, $red and terminate $loop and return;
         $red = read_exactly $rdr, my $buf, unpack 'I', $buf_len;
         recv_arg_error $log, $PID, $red and terminate $loop and return;

         try {
            my $param = $buf ? thaw $buf : [ $PID, {} ];
            my $rv    = $code->( @{ $param } );

            $wtr and send_msg $wtr, $log, 'SENDRV', $param->[ 0 ], $rv;
         }
         catch { $log->error( $lead.$_ ) };

         $max_calls and ++$count > $max_calls and terminate $loop;
         return;
      } );

      $loop->watch_signal( TERM => sub { terminate $loop } );
      $loop->start; $after and $after->( $self );
      return;
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Routine - One-line description of the modules purpose

=head1 Synopsis

   use Async::IPC::Routine;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

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

Copyright (c) 2014 Peter Flanigan. All rights reserved

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
