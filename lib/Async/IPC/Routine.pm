package Async::IPC::Routine;

use namespace::autoclean;

use Moo;
use Async::IPC::Channel;
use Async::IPC::Functions  qw( log_leader );
use Async::IPC::Process;
use Class::Usul::Constants qw( FALSE TRUE );
use Class::Usul::Functions qw( bson64id );
use Class::Usul::Types     qw( Bool CodeRef HashRef Object PositiveInt Undef );
use Try::Tiny;

extends q(Async::IPC::Base);

# Private functions
my $_build_call_ch = sub {
   my $self = shift;

   return Async::IPC::Channel->new
      ( builder     => $self->_usul,
        description => $self->description.' call channel',
        loop        => $self->loop,
        name        => $self->name.'_CALL_CH', );
};

my $_build_child = sub {
   return Async::IPC::Process->new
      ( { %{ $_[ 0 ]->child_args }, code => $_[ 0 ]->call_handler } );
};

my $_build_return_ch = sub {
   my $self = shift; $self->on_return or return;

   return Async::IPC::Channel->new
      ( builder     => $self->_usul,
        description => $self->description.' return channel',
        loop        => $self->loop,
        name        => $self->name.'_RETN_CH',
        on_recv     => $self->on_return,
        read_mode   => 'async', );
};

has 'call_ch'    => is => 'lazy', isa => Object,  builder  => $_build_call_ch;

has 'child'      => is => 'lazy', isa => Object,  builder  => $_build_child;

has 'child_args' => is => 'ro',   isa => HashRef, builder  => sub { {} };

has 'code'       => is => 'ro',   isa => CodeRef, required => TRUE;

has 'is_running' => is => 'rwp',  isa => Bool,    default  => FALSE;

has 'max_calls'  => is => 'ro',   isa => PositiveInt, default => 0;

has 'on_return'  => is => 'ro',   isa => CodeRef | Undef;

has 'return_ch'  => is => 'lazy', isa => Object  | Undef,
   builder       => $_build_return_ch;

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
   return $attr;
};

sub BUILD {
   my $self = shift; $self->autostart and $self->start; return;
}

sub DEMOLISH {
   $_[ 0 ]->stop; return;
}

# Public methods
sub call {
   my ($self, @args) = @_; $self->is_running or return; $args[ 0 ] ||= bson64id;

   return $self->call_ch ? $self->call_ch->send( [ @args ] ) : undef;
}

sub call_handler {
   my $self      = shift;
   my $code      = $self->code;
   my $max_calls = $self->max_calls;
   my $call_ch   = $self->call_ch;
   my $return_ch = $self->return_ch ? $self->return_ch : FALSE;

   return sub {
      my $self = shift; my $count = 0; my $log = $self->log;

      $call_ch->start( 'read' ); $return_ch and $return_ch->start( 'write' );

      while (1) {
         my $param;

         try {
            if ($param = $call_ch->recv) {
               my $rv = $code->( @{ $param } );

               $return_ch and $return_ch->send( [ $param->[ 0 ], $rv ] );
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
   $self->return_ch and $self->return_ch->start( 'read' );
   $self->call_ch   and $self->call_ch->start( 'write' );
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
