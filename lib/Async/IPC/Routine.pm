package Async::IPC::Routine;

use namespace::autoclean;

use Async::IPC::Constants qw( EXCEPTION_CLASS FALSE OK TRUE );
use Async::IPC::Functions qw( bson64id log_error terminate throw );
use Async::IPC::Types     qw( ArrayRef Bool CodeRef HashRef Maybe
                              Object PositiveInt );
use Ref::Util             qw( is_arrayref );
use Try::Tiny;
use Type::Utils           qw( enum );
use Unexpected::Functions qw( Unspecified );
use Moo;

extends q(Async::IPC::Base);

my $MODE_TYPE = enum 'MODE_TYPE' => [ 'async', 'sync' ];

=pod

=encoding utf-8

=head1 Name

Async::IPC::Routine - Call a method in a child process returning the result

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

=item C<after>

An optional code reference. Called after the event loop in the asyncronous call
handler stops

=cut

has 'after' => is => 'ro', isa => Maybe[CodeRef];

=item C<before>

An optional code reference. Called before the event loop in the asyncronous
call handler is started

=cut

has 'before' => is => 'ro', isa => Maybe[CodeRef];

=item C<call_ch_mode>

Must be a mode type. Either C<async> or C<sync>

=cut

has 'call_ch_mode' => is => 'lazy', isa => $MODE_TYPE;

=item C<call_chs>

An array reference of L<Async::IPC::Channel> objects used by the parent to send
call arguments to the child process. Built by default

=cut

has 'call_chs' => is => 'lazy', isa => ArrayRef[Object],
   builder     => '_build_call_chs';

=item C<child>

The child process object reference. An instance of L<Async::IPC::Process>.
Build by default

=cut

has 'child' => is => 'lazy', isa => Object, builder => '_build_child';

=item C<child_args>

A hash reference passed to the child process constructor

=cut

has 'child_args' => is => 'ro', isa => HashRef, builder => sub { {} };

=item C<is_running>

Boolean defaults to false. Set to true when L</start> is called. Set to false
when L</stop> is called

=cut

has 'is_running' => is => 'rwp', isa => Bool, default => FALSE;

=item C<max_calls>

Positive integer defaults to zero. The maximum number of calls to execute
before terminating. When zero do not terminate

=cut

has 'max_calls' => is => 'ro', isa => PositiveInt, default => 0;

=item C<on_recv>

An array reference of code references. At least one must be provided. This
is the code reference(s) called when arguments are received

=cut

has 'on_recv' => is => 'ro', isa => ArrayRef[CodeRef], builder => sub { [] };

=item C<on_return>

Invoke this callback subroutine when the code reference returns a value

=cut

has 'on_return' => is => 'ro', isa => ArrayRef[CodeRef], builder => sub { [] };

=item C<return_chs>

A L<Async::IPC::Channel> object used by the parent process to read the result
back from the child

=cut

has 'return_chs' => is => 'lazy', isa => ArrayRef[Object],
   builder       => '_build_return_chs';

=back

=head1 Subroutines/Methods

=head2 C<BUILDARGS>

Splits out the child constructor arguments

=cut

around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_;

   my $attr = $orig->($self, @args);
   my $args = { autostart => FALSE };

   for my $k (qw(child_args on_exit)) {
      my $v = delete $attr->{$k};

      $args->{$k} = $v if defined $v;
   }

   $attr->{child_args} = $args;

   $attr->{on_recv} = [$attr->{on_recv}] if exists $attr->{on_recv}
      && defined $attr->{on_recv} && !is_arrayref $attr->{on_recv};

   $attr->{on_return} = [$attr->{on_return}] if exists $attr->{on_return}
      && defined $attr->{on_return} && !is_arrayref $attr->{on_return};

   return $attr;
};

=head2 C<BUILD>

Raise an exception if there is not at least one C<on_recv> handler. Call
L</start> if C<autostart> is true

=cut

sub BUILD {
   my $self = shift;

   throw Unspecified, ['on_recv'] unless defined $self->on_recv->[0];

   $self->start if $self->autostart;

   return;
}

=head2 C<DEMOLISH>

Call L</stop> on destruction

=cut

sub DEMOLISH {
   my ($self, $gd) = @_;

   return if $gd;

   $self->stop;
   return;
}

=head2 C<async_call_handler>

   $code = $self->async_call_handler

Returns the code reference that implements an asyncronous event loop. This
loops until C<< loop->stop >> is called

=cut

sub async_call_handler {
   my $self       = shift;
   my $after      = $self->after;
   my $before     = $self->before;
   my $call_chs   = $self->call_chs;
   my $return_chs = $self->return_chs->[0] ? $self->return_chs : FALSE;

   return sub {
      my $self = shift;
      my $loop = $self->loop;

      $before->($self) if $before ; # Must fork before watching signals
      _start_channels($return_chs, 'write') if $return_chs;
      _start_channels($call_chs, 'read');
      $loop->watch_signal(TERM => sub { terminate $loop });
      $loop->start; # Loops here processing events until terminate is called
      $after->($self) if $after;
      $self->loop->watch_child(0); # Wait for child processes to exit
      return OK;
   };
};

=head2 C<call>

   $result = $routine->call( @args );

Call the code reference in the child process. See L</call_channel>

=cut

sub call {
   my ($self, @args) = @_;

   return $self->call_channel(0, @args);
}

=head2 C<call_channel>

   $result = $routine->call_channel( $channel_no, @args )

So long as C<is_running> is true send the C<args> to the child process on the
specified C<channel_no>

=cut

sub call_channel {
   my ($self, $channel_no, @args) = @_;

   return unless $self->is_running;

   $args[0] ||= bson64id; # First arg is unique and sent by the return channel

   return $self->call_chs->[$channel_no]->send([@args]);
}

=head2 C<pid>

   $int = $routine->pid

The id of the child process. Undefined if the child process is not running

=cut

sub pid {
   my $self = shift;

   return $self->is_running ? $self->child->pid : undef;
}

=head2 C<start>

   $bool = $routine->start

Starts the child process and the communication channel(s)

=cut

sub start {
   my $self = shift;

   return if $self->is_running;

   $self->_set_is_running(TRUE);
   $self->child->start;
   _start_channels($self->return_chs, 'read') if $self->return_chs->[0];
   _start_channels($self->call_chs, 'write');
   return TRUE;
}

=head2 C<stop>

   $bool = $routine->stop;

Stop the child process and communication channel(s)

=cut

sub stop {
   my $self = shift;

   return unless $self->is_running;

   $self->_set_is_running(FALSE);
   $self->child->stop;
   _stop_channels($self->return_chs, 'read') if $self->return_chs->[0];
   _stop_channels($self->call_chs, 'write');
   return TRUE;
}

=head2 C<sync_call_handler>

   $code = $self->sync_call_handler

Returns a code reference that blocks waiting for parameters to be received.
It calls the first of the C<on_recv> handlers and sends the result back on
the return channel

=cut

sub sync_call_handler {
   my $self       = shift;
   my $call_chs   = $self->call_chs;
   my $code       = $self->on_recv->[0];
   my $max_calls  = $self->max_calls;
   my $return_chs = $self->return_chs->[0] ? $self->return_chs : FALSE;

   return sub {
      my $self  = shift;
      my $count = 0;

      _start_channels($return_chs, 'write') if $return_chs;
      _start_channels($call_chs, 'read');

      while (1) {
         my $param;

         try {
            if (defined ($param = $call_chs->[0]->recv)) { # Blocks here
               my $rv = $code->($self, @{$param});

               if ($return_chs) {
                  my $ch_no = 0;

                  while (defined $return_chs->[$ch_no]) {
                     $return_chs->[$ch_no++]->send([$param->[0], $rv]);
                  }
               }
            }
         }
         catch { log_error $self, $_ };

         last unless defined $param;
         last if $max_calls and ++$count >= $max_calls;
      }

      return;
   };
}

# Private methods
sub _build_async_recv_handler {
   my ($self, $ch_no, $code) = @_;

   my $count     = 0;
   my $max_calls = $self->max_calls;
   my $return_ch = $self->return_chs->[$ch_no];

   return sub {
      my ($self, $param) = @_;

      try {
         my $rv = $code->($self, @{$param});

         $return_ch->send([$param->[0], $rv]) if $return_ch;
      }
      catch { log_error $self, $_ };

      terminate $self->loop if $max_calls and ++$count >= $max_calls;
      return TRUE;
   };
}

sub _build_call_ch_mode {
   my $self = shift;

   return (defined $self->on_recv->[1]) ? 'async' : 'sync';
}

sub _build_call_chs {
   my $self     = shift;
   my %args     = ();
   my $channels = [];
   my $ch_no    = 0;

   $args{read_mode}  = $self->call_ch_mode;
   $args{write_mode} = 'async';

   while (defined (my $code = $self->on_recv->[$ch_no])) {
      if ($args{read_mode} eq 'async') {
         $args{on_eof } = sub { terminate $_[0]->loop };
         $args{on_recv} = $self->_build_async_recv_handler($ch_no, $code);
      }

      push @{$channels}, $self->_build_channel('call', $ch_no, %args);
      delete $args{on_eof};
      delete $args{on_recv};
      $ch_no++;
   }

   return $channels;
}

sub _build_channel {
   my ($self, $dirn, $channel_no, %args) = @_;

   return $self->factory->new_notifier(
      type        => 'channel',
      name        => $self->name."_${dirn}_ch${channel_no}",
      description => $self->description." ${dirn} channel ${channel_no}",
      %args,
   );
}

sub _build_child {
   my $self = shift;
   my $code = $self->call_ch_mode eq 'async'
      ? $self->async_call_handler : $self->sync_call_handler;

   return $self->factory->new_notifier({
      type        => 'process',
      name        => $self->name,
      description => $self->description,
      code        => $code,
      %{ $self->child_args },
   });
}

sub _build_return_chs {
   my $self     = shift;
   my %args     = ();
   my $channels = [];
   my $ch_no    = 0;

   return $channels unless $self->on_return->[0];

   $args{read_mode} = 'async';

   while (defined ($args{on_recv} = $self->on_return->[$ch_no])) {
      push @{$channels}, $self->_build_channel('return', $ch_no, %args);
      delete $args{on_recv};
      $ch_no++;
   }

   return $channels;
}

# Private functions
sub _start_channels {
   my ($ch, $mode) = @_;

   my $i = 0;

   $ch->[$i++]->start($mode) while (defined $ch->[$i]);

   return;
}

sub _stop_channels {
   my ($ch, $mode) = @_;

   my $i = 0;

   $ch->[$i++]->stop($mode) while (defined $ch->[$i]);

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
