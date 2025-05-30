package Async::IPC::Process;

use namespace::autoclean;

use Async::IPC::Constants qw( FALSE TRUE );
use Async::IPC::Functions qw( log_debug log_info );
use Async::IPC::Types     qw( ArrayRef CodeRef HashRef
                              NonEmptySimpleStr Undef );
use English               qw( -no_match_vars );
use POSIX                 qw( WEXITSTATUS );
use Ref::Util             qw( is_coderef );
use Moo;

extends q(Async::IPC::Base);

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

=item C<child_args>

Optional hash reference passed to L<run command|Class::Usul::Cmd>

=cut

has 'child_args' => is => 'ro', isa => HashRef, builder => sub { {} };

=item C<code>

Required code reference / array reference / non empty simple string to execute
in the child process

=cut

has 'code'  => is => 'ro', isa => CodeRef|ArrayRef|NonEmptySimpleStr,
   required => TRUE;

=item C<on_exit>

The code reference to call when the process exits. The factory wraps this
reference to log when it's called

=cut

has 'on_exit' => is => 'ro', isa => CodeRef|Undef;

has '+pid' => builder => sub { 0 };

=back

=head1 Subroutines/Methods

=head2 C<BUILD>

Starts the child process, sets on exits and return callbacks

=cut

sub BUILD {
   my $self = shift;

   $self->start if $self->autostart;

   return;
}

=head2 C<DEMOLISH>

Stops the process prior to object destruction

=cut

sub DEMOLISH {
   my ($self, $gd) = @_;

   return if $gd;

   $self->stop;
   return;
}

=head2 C<is_running>

   $bool = $process->is_running;

Returns true if the child process is running

=cut

sub is_running {
   my $self = shift;

   return $self->pid ? CORE::kill 0, $self->pid : FALSE;
}

=head2 C<start>

   $process->start;

Start the child process

=cut

sub start {
   my $self = shift;

   return if $self->is_running;

   my $code = $self->code;
   my $temp = $self->config->tempdir;
   my $args = { %{$self->child_args}, async => TRUE, ignore_zombies => FALSE, };
   my $name = $self->config->script . ' - ' . (lc $self->name);
   my $cmd  = (is_coderef $code)
            ? [ $self->capture_weakself(sub {
                   $PROGRAM_NAME = $name; $code->(shift) }) ]
            : $code;

   $args->{err} = $temp->catfile( (lc $self->name) . '.err' ) if $self->debug;

   $self->_set_pid(my $pid = $self->run_cmd($cmd, $args)->pid);
   $self->_watch_child($pid);
   log_info $self, 'Started ' . $self->description;
   return TRUE;
}

=head2 C<stop>

   $process->stop;

Stop the child process

=cut

sub stop {
   my $self = shift;

   return unless $self->is_running;

   log_debug $self, 'Stopping '.$self->description;
   CORE::kill 'TERM', $self->pid;
   return TRUE;
}

# Private methods
sub _watch_child {
   my ($self, $pid) = @_;

   my $on_exit = sub {
      my $self = shift;
      my $pid  = shift;
      my $rv   = WEXITSTATUS(shift);

      log_info $self, ucfirst $self->description." stopped rv ${rv}";

      return $self->maybe_invoke_event('on_exit', $pid, $rv);
   };

   $self->loop->watch_child($pid, $self->capture_weakself($on_exit));
   return;
}

1;

__END__

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
