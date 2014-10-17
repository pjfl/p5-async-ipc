package Async::IPC::Loop;

use strictures;
use feature 'state';

use AnyEvent;
use Async::Interrupt;
use Class::Usul::Functions qw( arg_list );
use English                qw( -no_match_vars );
use Scalar::Util           qw( blessed );

my $Cache = {};

# Construction
sub new {
   my $self = shift; return bless arg_list( @_ ), blessed $self || $self;
}

# Public methods
sub start {
   my $self = shift; (local $self->{cv} = AnyEvent->condvar)->recv; return;
}

sub start_nb {
   my ($self, $cb) = @_;

   (local $self->{cv} = AnyEvent->condvar)->cb( sub {
      my @res = $_[ 0 ]->recv; defined $cb and $cb->( @res ) } );

   return;
}

sub stop {
   shift->{cv}->send( @_ ); return;
}

sub watch_child {
   my ($self, $id, $cb) = @_; my $w = $self->_events( 'watchers' );

   if ($id) {
      my $cv = $w->{ $id }->[ 0 ] = AnyEvent->condvar;

      $w->{ $id }->[ 1 ] = AnyEvent->child( pid => $id, cb => sub {
         defined $cb and $cb->( @_ ); $cv->send } );
   }
   else {
      for (sort { $a <=> $b } $cb ? $cb->() : keys %{ $w }) {
         $w->{ $_ } and $w->{ $_ }->[ 0 ] and $w->{ $_ }->[ 0 ]->recv;
         $self->unwatch_child( $_ );
      }
   }

   return;
}

sub unwatch_child {
   my $w = $_[ 0 ]->_events( 'watchers' ); my $id = $_[ 1 ];

   undef $w->{ $id }->[ 0 ]; undef $w->{ $id }->[ 1 ]; delete $w->{ $id };
   return;
}

sub watch_read_handle {
   my ($self, $fh, $cb) = @_; my $h = $self->_events( 'handles' );

   $h->{ "r${fh}" } = AnyEvent->io( cb => $cb, fh => $fh, poll => 'r' );
   return;
}

sub unwatch_read_handle {
   delete $_[ 0 ]->_events( 'handles' )->{ 'r'.$_[ 1 ] }; return;
}

sub watch_signal {
   my ($self, $signal, $cb) = @_; my $attaches;

   unless ($attaches = $self->_sigattaches->{ $signal }) {
      my $s = $self->_events( 'signals' ); my @attaches;

      $s->{ $signal } = AnyEvent->signal( signal => $signal, cb => sub {
         for my $attachment (@attaches) { $attachment->() }
      } );

      $attaches = $self->_sigattaches->{ $signal } = \@attaches;
   }

   push @{ $attaches }, $cb; return \$attaches->[ -1 ];
}

sub unwatch_signal {
   my ($self, $signal, $id) = @_;

   # Can't use grep because we have to preserve the addresses
   my $attaches = $self->_sigattaches->{ $signal } or return;

   for (my $i = 0; $i < @{ $attaches }; ) {
      not $id and splice @{ $attaches }, $i, 1, () and next;
      $id == \$attaches->[ $i ] and splice @{ $attaches }, $i, 1, () and last;
      $i++;
   }

   scalar @{ $attaches } and return;
   delete $self->_sigattaches->{ $signal };
   delete $self->_events( 'signals' )->{ $signal };
   return;
}

sub watch_time {
   my ($self, $id, $cb, $after, $interval) = @_;

   defined $interval and $interval eq 'abs' and $after -= time;
   defined $interval and $interval =~ m{ \A (?: abs | rel ) \z }mx
       and $interval = 0;

   $after > 0 or $after = 0; my @args = (after => $after, cb => $cb);

   not defined $interval and push @args, 'interval', $after;
       defined $interval and $interval and push @args, 'interval', $interval;

   my $t = $self->_events( 'timers' ); $t->{ $id }->[ 0 ] = $cb;

   $t->{ $id }->[ 1 ] = AnyEvent->timer( @args );
   return;
}

sub unwatch_time {
   my $t = $_[ 0 ]->_events( 'timers' ); my $id = $_[ 1 ];

   exists $t->{ $id } or return 0; my $cb = $t->{ $id }->[ 0 ];

   undef $t->{ $id }->[ 0 ]; undef $t->{ $id }->[ 1 ]; delete $t->{ $id };

   return $cb;
}

sub watch_write_handle {
   my ($self, $fh, $cb) = @_; my $h = $self->_events( 'handles' );

   $h->{ "w${fh}" } = AnyEvent->io( cb => $cb, fh => $fh, poll => 'w' );
   return;
}

sub unwatch_write_handle {
   delete $_[ 0 ]->_events( 'handles' )->{ 'w'.$_[ 1 ] }; return;
}

sub uuid {
   state $uuid //= 1; return $uuid++;
}

# Private methods
sub _events {
   return $Cache->{ $PID }->{ $_[ 1 ] } ||= {};
}

sub _sigattaches {
   return $Cache->{ $PID }->{_sigattaches} ||= {};
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Loop - One-line description of the modules purpose

=head1 Synopsis

   use Async::IPC::Loop;
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
