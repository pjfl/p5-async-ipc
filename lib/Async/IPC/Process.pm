package Async::IPC::Process;

use namespace::autoclean;

use Moo;
use Async::IPC::Functions  qw( log_leader );
use Class::Usul::Constants qw( FALSE TRUE );
use Class::Usul::Functions qw( is_coderef );
use Class::Usul::Types     qw( ArrayRef CodeRef NonEmptySimpleStr Undef );
use English                qw( -no_match_vars );
use POSIX                  qw( WEXITSTATUS );
use Scalar::Util           qw( weaken );

extends q(Async::IPC::Base);

# Private methods
my $_watch_child = sub {
   my ($self, $pid) = @_;

   my $on_exit = sub {
      my $self = shift; my $pid = shift; my $rv = WEXITSTATUS( shift );

      my $mesg = ucfirst $self->description." stopped rv ${rv}";

      $self->log->info( (log_leader 'info', $self->name, $pid).$mesg );

      return $self->on_exit ? $self->on_exit->( $self, $pid, $rv ) : TRUE;
   };

   $self->loop->watch_child( $pid, $self->capture_weakself( $on_exit ) );
   return;
};

# Public attributes
has 'code'    => is => 'ro', isa => CodeRef | ArrayRef | NonEmptySimpleStr,
   required   => TRUE;

has 'on_exit' => is => 'ro', isa => CodeRef | Undef;

# Construction
sub BUILD {
   my $self = shift; $self->autostart and $self->start; return;
}

sub DEMOLISH {
   my $self = shift; $self->stop; return;
}

# Public methods
sub is_running {
   my $self = shift; return $self->pid ? CORE::kill 0, $self->pid : FALSE;
}

sub start {
   my $self = shift; $self->is_running and return;
   my $code = $self->code;
   my $temp = $self->config->tempdir;
   my $args = { async => TRUE, ignore_zombies => FALSE };
   my $name = $self->config->pathname->abs2rel.' - '.(lc $self->name);
   my $cmd  = (is_coderef $code)
            ? [ $self->capture_weakself( sub {
                   $PROGRAM_NAME = $name; $code->( shift ) } ) ]
            : $code;

   $self->debug and $args->{err} = $temp->catfile( (lc $self->name).'.err' );

   $self->_set_pid( my $pid = $self->run_cmd( $cmd, $args )->pid );

   $self->$_watch_child( $pid ); my $mesg = 'Started '.$self->description;

   $self->log->info( (log_leader 'info', $self->name, $pid).$mesg );
   return TRUE;
}

sub stop {
   my $self = shift; $self->is_running or return;

   my $mesg = 'Stopping '.$self->description;

   $self->log->debug( (log_leader 'debug', $self->name, $self->pid).$mesg );
   CORE::kill 'TERM', $self->pid;
   return TRUE;
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
         name => 'logger key used to identify a log entry',
         type => 'process', );

=head1 Description

Execute a child process with input / output channels

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<code>

Required code reference / array reference / non empty simple string to execute
in the child process

=item C<on_exit>

The code reference to call when the process exits. The factory wraps this
reference to log when it's called

=back

=head1 Subroutines/Methods

=head2 C<BUILD>

Starts the child process, sets on exits and return callbacks

=head2 C<is_running>

   $bool = $process->is_running;

Returns true if the child process is running

=head2 C<start>

   $process->start;

Start the child process

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
