package Async::IPC::Function;

use feature 'state';
use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader read_exactly
                               recv_arg_error send_msg );
use Async::IPC::Process;
use Class::Usul::Constants qw( FALSE OK TRUE );
use Class::Usul::Functions qw( bson64id nonblocking_write_pipe_pair throw );
use Class::Usul::Types     qw( ArrayRef Bool HashRef
                               NonZeroPositiveInt PositiveInt SimpleStr );
use English                qw( -no_match_vars );
use Storable               qw( thaw );
use Try::Tiny;

extends q(Async::IPC::Base);

# Public attributes
has 'channels'       => is => 'ro',  isa => SimpleStr, default => 'i';

has 'is_running'     => is => 'rwp', isa => Bool, default => TRUE;

has 'max_calls'      => is => 'ro',  isa => PositiveInt, default => 0;

has 'max_workers'    => is => 'ro',  isa => NonZeroPositiveInt, default => 1;

has 'worker_args'    => is => 'ro',  isa => HashRef,  default => sub { {} };

has 'worker_index'   => is => 'ro',  isa => ArrayRef, default => sub { [] };

has 'worker_objects' => is => 'ro',  isa => HashRef,  default => sub { {} };

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $args = $orig->( $self, @args );

   my $attr = { builder     => $args->{builder},
                description => $args->{description}, };

   for my $k ( qw( autostart channels log_key max_calls max_workers ) ) {
      my $v = delete $args->{ $k }; defined $v and $attr->{ $k } = $v;
   }

   $attr->{worker_args} = $args;
   return $attr;
};

sub BUILD {
   my $self = shift; $self->autostart or return;

   $self->_next_worker for (0 .. $self->max_workers - 1);

   return;
}

# Public methods
sub call {
   my ($self, @args) = @_; $self->is_running or return FALSE;

   $args[ 0 ] ||= bson64id; return $self->_next_worker->send( @args );
}

sub set_return_callback {
   my ($self, $code) = @_; my $workers = $self->worker_objects;

   $workers->{ $_ }->set_return_callback( $code ) for (keys %{ $workers });

   return;
}

sub stop {
   my $self = shift; $self->_set_is_running( FALSE );

   my $lead = log_leader 'debug', $self->log_key, $self->pid;

   $self->log->debug( $lead.'Stopping '.$self->description.' pool' );

   my $workers = $self->worker_objects; my @pids = keys %{ $workers };

   $workers->{ $_ }->stop for (@pids);

   $self->loop->watch_child( 0, sub { @pids } );
   return;
}

# Private methods
sub _build_pid {
   return $_[ 0 ]->loop->uuid;
}

sub _new_worker {
   my ($self, $index) = @_; my $args = { %{ $self->worker_args } };

   my $on_exit = delete $args->{on_exit}; my $workers = $self->worker_objects;

   $self->channels =~ m{ i }mx
      and $args->{call_pipe} = nonblocking_write_pipe_pair;
  ($self->channels =~ m{ o }mx or exists $args->{on_return})
      and $args->{retn_pipe} = nonblocking_write_pipe_pair;
   $args->{code       } = __call_handler( $args );
   $args->{description} = (lc $self->log_key)." worker ${index}";
   $args->{log_key    } = 'WORKER';
   $args->{on_exit    } = sub { delete $workers->{ $_[ 0 ] }; $on_exit->( @_ )};

   my $worker = Async::IPC::Process->new( $args ); my $pid = $worker->pid;

   $workers->{ $pid } = $worker; $self->worker_index->[ $index ] = $pid;

   return $worker;
}

sub _next_worker {
   my $self  = shift;
   my $index = $self->_next_worker_index;
   my $pid   = $self->worker_index->[ $index ] || 0;

   return $self->worker_objects->{ $pid } || $self->_new_worker( $index );
}

sub _next_worker_index {
   my $self = shift; state $worker //= -1;

   $worker++; $worker >= $self->max_workers and $worker = 0;

   return $worker;
}

# Private functions
sub __call_handler {
   my $args = shift;
   my $code = delete $args->{code};
   my $rdr  = $args->{call_pipe} ? $args->{call_pipe}->[ 0 ] : FALSE;
   my $wtr  = $args->{retn_pipe} ? $args->{retn_pipe}->[ 1 ] : FALSE;

   return sub {
      my $self = shift;
      my $lead = log_leader 'error', 'EXCODE', $PID;
      my $log  = $self->log; my $max = $self->max_calls; my $count = 0;

      while (TRUE) {
         $max and ++$count > $max and last;

         my $red = read_exactly $rdr, my $buf_len, 4; # Block here

         recv_arg_error $log, $PID, $red and last;
         $red = read_exactly $rdr, my $buf, unpack 'I', $buf_len;
         recv_arg_error $log, $PID, $red and last;

         try {
            my $param = $buf ? thaw $buf : [ $PID, {} ];
            my $rv    = $code->( @{ $param } );

            $wtr and send_msg $wtr, $log, 'SENDRV', $param->[ 0 ], $rv;
         }
         catch { $log->error( $lead.$_ ) };
      }

      return;
   }
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Function - One-line description of the modules purpose

=head1 Synopsis

   use Async::IPC::Function;
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
