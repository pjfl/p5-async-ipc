package Async::IPC::Function;

use feature 'state';
use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader read_exactly
                               recv_arg_error send_msg );
use Async::IPC::Process;
use Class::Usul::Constants qw( FALSE OK TRUE );
use Class::Usul::Functions qw( bson64id nonblocking_write_pipe_pair throw );
use Class::Usul::Types     qw( ArrayRef Bool HashRef NonZeroPositiveInt
                               PositiveInt SimpleStr );
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

# Private functions
my $_call_handler = sub {
   my $args = shift;
   my $code = $args->{code};
   my $rdr  = $args->{call_pipe} ? $args->{call_pipe}->[ 0 ] : FALSE;
   my $wtr  = $args->{retn_pipe} ? $args->{retn_pipe}->[ 1 ] : FALSE;

   return sub {
      my $self = shift;
      my $lead = log_leader 'error', 'EXCODE', $PID;
      my $log  = $self->log; my $max = $self->max_calls; my $count = 0;

      while (not $max or $count++ < $max) {
         my $red = read_exactly $rdr, my $buf_len, 4; # Block here

         recv_arg_error $log, $PID, $red and return;
         $red = read_exactly $rdr, my $buf, unpack 'I', $buf_len;
         recv_arg_error $log, $PID, $red and return;

         try {
            my $param = $buf ? thaw $buf : [ $PID, {} ];
            my $rv    = $code->( @{ $param } );

            $wtr and send_msg $wtr, $log, 'SENDRV', $param->[ 0 ], $rv;
         }
         catch { $log->error( $lead.$_ ) };
      }

      return;
   }
};

# Private methods
my $_new_worker = sub {
   my ($self, $index) = @_; my $args = { %{ $self->worker_args } };

   my $on_exit = $args->{on_exit}; my $workers = $self->worker_objects;

   $self->channels =~ m{ i }mx
      and $args->{call_pipe} = nonblocking_write_pipe_pair;
  ($self->channels =~ m{ o }mx or exists $args->{on_return})
      and $args->{retn_pipe} = nonblocking_write_pipe_pair;
   $args->{code} = $_call_handler->( $args );
   $args->{description} .= " ${index}";
   $args->{on_exit} = sub { delete $workers->{ $_[ 0 ] }; $on_exit->( @_ ) };

   my $worker = Async::IPC::Process->new( $args ); my $pid = $worker->pid;

   $workers->{ $pid } = $worker; $self->worker_index->[ $index ] = $pid;

   return $worker;
};

my $_next_worker_index = sub {
   my $self = shift; state $worker //= -1;

   $worker++; $worker >= $self->max_workers and $worker = 0;

   return $worker;
};

my $_next_worker = sub {
   my $self  = shift;
   my $index = $self->$_next_worker_index;
   my $pid   = $self->worker_index->[ $index ] || 0;

   return $self->worker_objects->{ $pid } || $self->$_new_worker( $index );
};

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = {};

   my $args = $orig->( $self, @args ); $args->{description} .= ' worker';

   for my $k ( qw( builder description loop max_calls ) ) {
      defined $args->{ $k } and $attr->{ $k } = $args->{ $k };
   }

   for my $k ( qw( autostart channels log_key max_workers ) ) {
      my $v = delete $args->{ $k }; defined $v and $attr->{ $k } = $v;
   }

   $args->{log_key    } = delete $args->{worker_key} || 'WORKER';
   $attr->{worker_args} = $args;
   return $attr;
};

sub BUILD {
   my $self = shift; $self->autostart or return;

   $self->$_next_worker for (0 .. $self->max_workers - 1);

   return;
}

sub _build_pid {
   return $_[ 0 ]->loop->uuid;
}

# Public methods
sub call {
   my ($self, @args) = @_; $self->is_running or return FALSE;

   $args[ 0 ] ||= bson64id; return $self->$_next_worker->send( @args );
}

sub set_return_callback {
   my ($self, @args) = @_; my $workers = $self->worker_objects;

   $workers->{ $_ }->set_return_callback( @args ) for (keys %{ $workers });

   return;
}

sub stop {
   my $self = shift; $self->_set_is_running( FALSE );

   my $lead = log_leader 'debug', $self->log_key, $self->pid;

   $self->log->debug( "${lead}Stopping ".$self->description.' pool' );

   my $workers = $self->worker_objects; my @pids = keys %{ $workers };

   $workers->{ $_ }->stop for (@pids);

   $self->loop->watch_child( 0, sub { @pids } );
   return;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Function - Implements a worker pool of processes

=head1 Synopsis

   use Async::IPC;

   my $factory = Async::IPC->new( builder => Class::Usul->new );

   my $function = $factory->new_notifier
      (  channels    => 'io',
         code        => sub { ... code to run in a child process ... },
         desc        => 'description used by the logger',
         key         => 'logger key used to identify a log entry',
         max_calls   => $max_ssh_worker_calls,
         max_workers => $max_ssh_workers,
         type        => 'function',
         worker_key  => 'logger key used to identify a worker log entry', );

   # Select a worker from the pool call it and return the result
   my $result = $function->call( @args );

=head1 Description

Each worker in the pool blocks reading on a pipe until it's called with the
arguments to pass to the code reference. Workers are called round-robin

=head1 Configuration and Environment

Inherits from L<Async::IPC::Base>. Defines the following additional attributes;

=over 3

=item C<channels>

Read only simple string. Can be C<i> for input, C<o> for output or
both. Defaults to C<i>. Creates pipes for input and / or output

=item C<is_running>

Boolean defaults to true. Set to false when the L</stop> method is called.
When false calls to L</call> return false and are a no-op

=item C<max_calls>

Positive integer, defaults to zero. If zero then workers will B<not> terminate
after a given number of calls. All other values limit the worker to that
number of calls before it terminates. Terminated workers are automatically
replaced on demand by the pool manager

=item C<max_workers>

Non zero positive integer, default to one. The number of workers in the pool

=item C<worker_args>

The hash reference of arguments passed to the worker constructor method. It
is assembled by the L</BUILDARGS> method from the arguments passed to this
classes constructor

=item C<worker_index>

An array reference of process ids. Each 'slot' in the index corresponds to
a worker process

=item C<worker_key>

A simple string. Logger key used to identify a worker log entry

=item C<worker_objects>

A hash reference of L<Async::IPC::Process> object references

=back

=head1 Subroutines/Methods

=head2 C<BUILDARGS>

Separates the worker parameters from pool parameters

=head2 C<BUILD>

If the L<autostart|Async::IPC::Base/autostart> attribute is true, start all of
the worker processes in the pool

=head2 C<call>

   $result = $function->call( @args );

Call the next worker in the pool passing in the arguments and returning the
result (if there is one and it is required)

=head2 C<set_return_callback>

   $function->set_return_callback( @args );

Set the return callback subroutine in each of the worker processes

=head2 C<stop>

   $function->stop;

Stop all of the workers in the pool

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<Moo>

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
