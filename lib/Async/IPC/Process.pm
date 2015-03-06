package Async::IPC::Process;

use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader read_exactly recv_rv_error send_msg );
use Class::Usul::Constants qw( FALSE SPC TRUE );
use Class::Usul::Functions qw( is_coderef throw );
use Class::Usul::Types     qw( ArrayRef CodeRef NonEmptySimpleStr
                               Object PositiveInt Undef );
use English                qw( -no_match_vars );
use Scalar::Util           qw( weaken );
use Try::Tiny;

extends q(Async::IPC::Base);

# Public attributes
has 'call_ch'   => is => 'ro', isa => Object;

has 'code'      => is => 'ro', isa => CodeRef | ArrayRef | NonEmptySimpleStr,
   required     => TRUE;

has 'max_calls' => is => 'ro', isa => PositiveInt, default => 0;

has 'on_exit'   => is => 'ro', isa => CodeRef | Undef;

has 'on_recv'   => is => 'ro', isa => CodeRef | Undef;

has 'return_ch' => is => 'ro', isa => Object | Undef;

# Construction
sub BUILD {
   my $self = shift; $self->autostart and $self->start; return;
}

# Public methods
sub is_running {
   my $self = shift; return $self->pid ? CORE::kill 0, $self->pid : FALSE;
}

sub send {
   my $self = shift; return $self->call_ch->send( [ @_ ] );
}

sub set_recv_callback {
   my ($self, $code, $loop) = @_; # TODO: The loop thing

   my $return_ch = $self->return_ch
      or throw 'Cannot set receiving callback without a return channel';

   $return_ch->recv( on_recv => $code ); $return_ch->start( 'read' );

   return;
}

sub start {
   my $self = shift; weaken $self; $self->is_running and return;
   my $code = $self->code;
   my $temp = $self->config->tempdir;
   my $args = { async => TRUE, ignore_zombies => FALSE };
   my $name = $self->config->pathname->abs2rel.' - '.(lc $self->name);
   my $cmd  = (is_coderef $code)
            ? [ sub { $PROGRAM_NAME = $name; $code->( $self ) } ]
            : $code;

   $self->debug and $args->{err} = $temp->catfile( (lc $self->name).'.err' );

   $self->_set_pid( my $pid = $self->run_cmd( $cmd, $args )->pid );

   $self->on_exit and $self->loop->watch_child( $pid, $self->on_exit );
   $self->on_recv and $self->set_recv_callback( $self->on_recv );
   $self->call_ch->start( 'write' );
   return;
}

sub stop {
   my $self = shift; $self->is_running or return;

   my $lead = log_leader 'debug', $self->name, $self->pid;

   $self->log->debug( "${lead}Stopping ".$self->description );
   CORE::kill 'TERM', $self->pid;
   return;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Process - Execute a child process with input / output channels

=head1 Synopsis

   use Async::IPC;

   my $factory = Async::IPC->new( builder => Class::Usul->new );

   my $process = $factory->new_notifier
      (  code => sub { ... code to run in a child process ... },
         desc => 'description used by the logger',
         key  => 'logger key used to identify a log entry',
         type => 'process', );

=head1 Description

Execute a child process with input / output channels

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<code>

Required code reference / array reference / non empty simple string to execute
in the child process

=item C<max_calls>

Positive integer defaults to zero. The maximum number of calls to execute
before terminating. When zero do not terminate

=item C<on_exit>

The code reference to call when the process exits. The factory wraps this
reference to log when it's called

=item C<on_recv>

Invoke this callback subroutine when the code reference returns a value

=item C<reader>

File handle used by the parent process to read the result back from
the child

=item C<writer>

File handle used by the parent to send call arguments to the child process

=back

=head1 Subroutines/Methods

=head2 C<BUILDARGS>

Selects the parents file handles for communication with the child process

=head2 C<BUILD>

Starts the child process, sets on exits and return callbacks

=head2 C<is_running>

   $bool = $process->is_running;

Returns true if the child process is running

=head2 C<send>

   $bool = $process->send( @args );

Returns true on success, false otherwise. Sends arguments to the child process

=head2 C<set_recv_callback>

   $process->set_recv_callback( $code, $loop );

Sets the receiving callback to the specified code reference. If C<$loop>
is specified use that loop object as opposed to ours

=head2 C<stop>

   $process->stop;

Stop the child process

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<Moo>

=item L<Storable>

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
