package Async::IPC::Semaphore;

use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader read_exactly recv_arg_error
                               send_msg terminate );
use Async::IPC::Loop;
use Async::IPC::Process;
use Class::Usul::Constants qw( FALSE TRUE );
use Class::Usul::Functions qw( bson64id nonblocking_write_pipe_pair );
use Class::Usul::Types     qw( Bool HashRef Object );
use English                qw( -no_match_vars );
use Scalar::Util           qw( refaddr );
use Storable               qw( thaw );
use Try::Tiny;

extends q(Async::IPC::Base);

has 'child'      => is => 'lazy', isa => Object,  builder => sub {
   Async::IPC::Process->new( $_[ 0 ]->child_args ) };

has 'child_args' => is => 'lazy', isa => HashRef, default => sub { {} };

has 'is_running' => is => 'rwp',  isa => Bool,    default => TRUE;

# Private functions
my $_call_handler = sub {
   my $args   = shift;
   my $before = delete $args->{before};
   my $_code  = delete $args->{code  };
   my $after  = delete $args->{after };
   my $lock   = $args->{builder}->lock;
   my $rdr    = $args->{call_pipe} ? $args->{call_pipe}->[ 0 ] : FALSE;
   my $wtr    = $args->{retn_pipe} ? $args->{retn_pipe}->[ 1 ] : FALSE;
   my $code   = sub { $lock->reset( k => $_[ 0 ] ); $_code->( @_ ) };

   return sub {
      my $self  = shift;
      my $count = 0; my $lead = log_leader 'error', 'EXCODE', $PID;
      my $log   = $self->log; my $max_calls = $self->max_calls;


      $self->_set_loop( my $loop = Async::IPC::Loop->new );
      $before and $before->( $self );

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

         $max_calls and ++$count >= $max_calls and terminate $loop;
         return;
      } );

      $loop->watch_signal( TERM => sub { terminate $loop } );
      $loop->start; $after and $after->( $self );
      return;
   };
};

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $args = $orig->( $self, @args ); my $attr;

   for my $k ( qw( builder description loop name ) ) {
      $attr->{ $k } = $args->{ $k };
   }

   for my $k ( qw( autostart ) ) {
      my $v = delete $args->{ $k }; defined $v and $attr->{ $k } = $v;
   }

   $args->{retn_pipe } = nonblocking_write_pipe_pair if ($args->{on_return});
   $args->{call_pipe } = nonblocking_write_pipe_pair;
   $args->{code      } = $_call_handler->( $args );
   $attr->{child_args} = $args;
   return $attr;
};

sub _build_pid {
   return $_[ 0 ]->child->pid;
}

# Public methods
sub call {
   my ($self, @args) = @_; $self->is_running or return FALSE;

   $args[ 0 ] ||= bson64id; return $self->child->send( @args );
}

# Public methods
sub raise {
   my $self = shift; $self->is_running or return FALSE; my $key = refaddr $self;

   $self->lock->set( k => $key, async => TRUE ) or return TRUE;

   return $self->call( $key );
}

sub stop {
   my $self = shift;

   $self->is_running or return; $self->_set_is_running( FALSE );

   my $pid  = $self->child->pid; $self->child->stop;

   $self->loop->watch_child( 0, sub { $pid } ); return;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Semaphore - Sub class of Routine with semaphore semantics

=head1 Synopsis

   use Async::IPC;

   my $factory = Async::IPC->new( builder => Class::Usul->new );

   my $semaphore = $factory->new_notifier
      (  code => sub { ... code to run in a child process ... },
         desc => 'description used by the logger',
         key  => 'logger key used to identify a log entry',
         type => 'semaphore' );

   my $result = $semaphore->call( @args );

=head1 Description

Sub class of L<Async::IPC::Routine> with semaphore semantics

=head1 Configuration and Environment

Defines no attributes

=head1 Subroutines/Methods

=head2 C<BUILDARGS>

Wraps the code reference. When called it will reset the lock set by the
L</raise> call

=head2 C<raise>

Call the child process, setting a semaphore

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<Moo>

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
