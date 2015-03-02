package Async::IPC::Routine;

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
   my $code   = delete $args->{code  };
   my $after  = delete $args->{after };
   my $rdr    = $args->{call_pipe} ? $args->{call_pipe}->[ 0 ] : FALSE;
   my $wtr    = $args->{retn_pipe} ? $args->{retn_pipe}->[ 1 ] : FALSE;

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

   for my $k ( qw( builder description log_key loop ) ) {
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

Async::IPC::Routine - Call a method is a child process returning the result

=head1 Synopsis

   use Async::IPC;

   my $factory = Async::IPC->new( builder => Class::Usul->new );

   my $routine = $factory->new_notifier
      (  code => sub { ... code to run in a child process ... },
         desc => 'description used by the logger',
         key  => 'logger key used to identify a log entry',
         type => 'routine' );

   my $result = $routine->call( @args );

=head1 Description

Call a method is a child process returning the result

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<child>

The child process object reference. An instance of L<Async::IPC::Process>

=item C<child_args>

A hash reference passed to the child process constructor

=item C<is_running>

Boolean defaults to true. Set to false when L</stop> is called

=back

=head1 Subroutines/Methods

=head2 C<BUILDARGS>

Splits out the child constructor arguments

=head2 C<call>

   $result = $routine->call( @args );

Call the code reference in the child process so long as C<is_running> is
true

=head2 C<stop>

   $routine->stop;

Stop the child process

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<Moo>

=item L<Storable>

=item L<Try::Tiny>

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
