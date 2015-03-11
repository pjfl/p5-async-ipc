package Async::IPC::Routine;

use namespace::autoclean;

use Moo;
use Async::IPC::Channel;
use Async::IPC::Functions  qw( log_leader terminate );
use Async::IPC::Process;
use Class::Usul::Constants qw( EXCEPTION_CLASS FALSE TRUE );
use Class::Usul::Functions qw( bson64id is_arrayref throw );
use Class::Usul::Types     qw( ArrayRef Bool CodeRef
                               HashRef Object PositiveInt );
use Try::Tiny;
use Unexpected::Functions  qw( Unspecified );

extends q(Async::IPC::Base);

# Private functions
my $_start_channels = sub {
   my ($ch, $mode) = @_; my $i = 0;

   $ch->[ $i++ ]->start( $mode ) while (defined $ch->[ $i ]);

   return;
};

# Construction methods
my $_build_channel = sub {
   my ($self, $dirn, $channel_no, %args) = @_;

   return Async::IPC::Channel->new
      ( builder     => $self->_usul,
        description => $self->description." ${dirn} channel ${channel_no}",
        loop        => $self->loop,
        name        => $self->name."_${dirn}_ch${channel_no}",
        %args );
};

my $_build_async_recv_handler = sub {
   my ($self, $ch_no, $code) = @_;

   my $count     = 0;
   my $max_calls = $self->max_calls;
   my $return_ch = $self->return_chs->[ $ch_no ];

   return sub {
      my ($self, $param) = @_; my $log = $self->log;

      try {
         my $rv = $code->( $self, @{ $param } );

         $return_ch and $return_ch->send( [ $param->[ 0 ], $rv ] );
      }
      catch { $log->error( (log_leader 'error', $self->name, $self->pid).$_ ) };

      $max_calls and ++$count >= $max_calls and terminate $self->loop;
      return TRUE;
   };
};

my $_build_call_chs = sub {
   my $self = shift; my %args = (); my $channels = []; my $ch_no = 0;

   $args{read_mode} = (defined $self->on_recv->[ 1 ]) ? 'async' : 'sync';

   while (defined (my $code = $self->on_recv->[ $ch_no ])) {
      if ($args{read_mode} eq 'async') {
         $args{on_eof } = sub { terminate $_[ 0 ]->loop };
         $args{on_recv} = $self->$_build_async_recv_handler( $ch_no, $code );
      }

      push @{ $channels }, $self->$_build_channel( 'call', $ch_no, %args );
      delete $args{on_eof}; delete $args{on_recv}; $ch_no++;
   }

   return $channels;
};

my $_build_child = sub {
   my $self = shift;

   return Async::IPC::Process->new
      ( { %{ $self->child_args },
          code => (defined $self->on_recv->[ 1 ])
               ?  $self->async_call_handler : $self->sync_call_handler } );
};

my $_build_return_chs = sub {
   my $self = shift; my %args = (); my $channels = []; my $ch_no = 0;

   $self->on_return->[ 0 ] or return; $args{read_mode} = 'async';

   while (defined ($args{on_recv} = $self->on_return->[ $ch_no ])) {
      push @{ $channels }, $self->$_build_channel( 'return', $ch_no, %args );
      delete $args{on_recv}; $ch_no++;
   }

   return $channels;
};

has 'call_chs'   => is => 'lazy', isa => ArrayRef[Object],
   builder       => $_build_call_chs;

has 'child'      => is => 'lazy', isa => Object,  builder => $_build_child;

has 'child_args' => is => 'ro',   isa => HashRef, builder => sub { {} };

has 'is_running' => is => 'rwp',  isa => Bool,    default => FALSE;

has 'max_calls'  => is => 'ro',   isa => PositiveInt, default => 0;

has 'on_recv'    => is => 'ro',   isa => ArrayRef[CodeRef],
   builder       => sub { [] };

has 'on_return'  => is => 'ro',   isa => ArrayRef[CodeRef],
   builder       => sub { [] };

has 'return_chs' => is => 'lazy', isa => ArrayRef[Object],
   builder       => $_build_return_chs;

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   my $args = { autostart => FALSE };

   for my $k ( qw( builder description loop name ) ) {
      $args->{ $k } = $attr->{ $k };
   }

   for my $k ( qw( on_exit ) ) {
      my $v = delete $attr->{ $k }; defined $v and $args->{ $k } = $v;
   }

   $attr->{child_args} = $args;
   exists $attr->{on_recv} and defined $attr->{on_recv}
      and not is_arrayref $attr->{on_recv}
      and $attr->{on_recv} = [ $attr->{on_recv} ];
   exists $attr->{on_return} and defined $attr->{on_return}
      and not is_arrayref $attr->{on_return}
      and $attr->{on_return} = [ $attr->{on_return} ];
   return $attr;
};

sub BUILD {
   my $self = shift;

   defined $self->on_recv->[ 0 ] or throw Unspecified, [ 'on_recv' ];

   $self->autostart and $self->start;
   return;
}

sub DEMOLISH {
   $_[ 0 ]->stop; return;
}

# Public methods
sub async_call_handler {
   my $self       = shift;
   my $call_chs   = $self->call_chs;
   my $return_chs = $self->return_chs->[ 0 ] ? $self->return_chs : FALSE;

   return sub {
      my $self = shift; $self->_set_loop( my $loop = Async::IPC::Loop->new );

      $return_chs and $_start_channels->( $return_chs, 'write' );
      $_start_channels->( $call_chs, 'read' );
      $loop->watch_signal( TERM => sub { terminate $loop } );
      $loop->start;
      return;
   };
};

sub call {
   my ($self, @args) = @_; return $self->call_channel( 0, @args );
}

sub call_channel {
   my ($self, $channel_no, @args) = @_;

   $self->is_running or return; $args[ 0 ] ||= bson64id;

   return $self->call_chs->[ $channel_no ]->send( [ @args ] );
}

sub sync_call_handler {
   my $self       = shift;
   my $call_chs   = $self->call_chs;
   my $code       = $self->on_recv->[ 0 ];
   my $max_calls  = $self->max_calls;
   my $return_chs = $self->return_chs->[ 0 ] ? $self->return_chs : FALSE;

   return sub {
      my $self = shift; my $count = 0; my $log = $self->log;

      $return_chs and $_start_channels->( $return_chs, 'write' );
      $_start_channels->( $call_chs, 'read' );

      while (1) {
         my $param;

         try {
            if (defined ($param = $call_chs->[ 0 ]->recv)) {
               my $rv = $code->( $self, @{ $param } );

               if ($return_chs) {
                  my $ch_no = 0;

                  while (defined $return_chs->[ $ch_no ]) {
                     $return_chs->[ $ch_no++ ]->send( [ $param->[ 0 ], $rv ] );
                  }
               }
            }
         }
         catch {
            $log->error( (log_leader 'error', $self->name, $self->pid).$_ );
         };

         defined $param or last; $max_calls and ++$count >= $max_calls and last;
      }

      return;
   };
}

sub pid {
   my $self = shift; return $self->is_running ? $self->child->pid : undef;
}

sub start {
   my $self = shift;

   $self->is_running and return; $self->_set_is_running( TRUE );

   $self->child->start;
   $self->return_chs->[ 0 ] and $_start_channels->( $self->return_chs, 'read' );
   $_start_channels->( $self->call_chs, 'write' );
   return TRUE;
}

sub stop {
   my $self = shift;

   $self->is_running or return; $self->_set_is_running( FALSE );

   $self->child->stop;
   return TRUE;
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

=item C<call_ch>

A L<Async::IPC::Channel> object used by the parent to send call arguments to
the child process

=item C<child>

The child process object reference. An instance of L<Async::IPC::Process>

=item C<child_args>

A hash reference passed to the child process constructor

=item C<is_running>

Boolean defaults to true. Set to false when L</stop> is called

=item C<max_calls>

Positive integer defaults to zero. The maximum number of calls to execute
before terminating. When zero do not terminate

=item C<on_return>

Invoke this callback subroutine when the code reference returns a value

=item C<return_ch>

A L<Async::IPC::Channel> object used by the parent process to read the result
back from the child

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
