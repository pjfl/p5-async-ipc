package Async::IPC::Routine;

use namespace::autoclean;

use Moo;
use Async::IPC::Channel;
use Async::IPC::Functions  qw( log_leader );
use Async::IPC::Process;
use Class::Usul::Constants qw( FALSE TRUE );
use Class::Usul::Functions qw( bson64id );
use Class::Usul::Types     qw( Bool HashRef Object );
use Try::Tiny;

extends q(Async::IPC::Base);

has 'child'      => is => 'lazy', isa => Object,  builder => sub {
   Async::IPC::Process->new( $_[ 0 ]->child_args ) };

has 'child_args' => is => 'lazy', isa => HashRef, default => sub { {} };

has 'is_running' => is => 'rwp',  isa => Bool,    default => FALSE;

# Private functions
my $_call_handler = sub {
   my $args      = shift;
   my $code      = delete $args->{code};
   my $call_ch   = $args->{call_ch  };
   my $return_ch = $args->{return_ch} ? $args->{return_ch} : FALSE;

   return sub {
      my $self = shift; my $count = 0; my $max_calls = $self->max_calls;

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
            my $lead = log_leader 'error', $self->name, $self->pid;

            $self->log->error( $lead.$_ );
         };

         defined $param or last; $max_calls and ++$count >= $max_calls and last;
      }

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

   $args->{on_return} and $args->{return_ch} = Async::IPC::Channel->new
      ( builder     => $attr->{builder},
        description => $attr->{description}.' return channel',
        loop        => $attr->{loop},
        name        => $attr->{name}.'_RETN_CH',
        on_recv     => delete $args->{on_return},
        read_mode   => 'async', );
   $args->{call_ch} = Async::IPC::Channel->new
      ( builder     => $attr->{builder},
        description => $attr->{description}.' call channel',
        loop        => $attr->{loop},
        name        => $attr->{name}.'_CALL_CH', );
   $args->{code      } = $_call_handler->( $args );
   $args->{autostart } = FALSE;
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

   return $self->child->send( @args );
}

sub pid {
   my $self = shift; return $self->is_running ? $self->child->pid : FALSE;
}

sub start {
   my $self = shift;

   $self->is_running and return; $self->_set_is_running( TRUE );

   return $self->child->start;
}

sub stop {
   my $self = shift;

   $self->is_running or return; $self->_set_is_running( FALSE );

   $self->child->stop;
   return;
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
