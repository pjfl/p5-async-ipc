package Async::IPC::Semaphore;

use namespace::autoclean;

use Moo;
use Class::Usul::Constants qw( TRUE );
use Scalar::Util           qw( refaddr );

extends q(Async::IPC::Routine);

# Private functions
# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   my $lock = $attr->{builder}->lock;
   my $code = $attr->{on_recv}->[ 0 ]; $attr->{on_recv}->[ 0 ] = sub {
      $lock->reset( k => $_[ 1 ] ); $code->( @_ );
   };

   return $attr;
};

sub raise {
   my $self = shift; $self->is_running or return; my $key = refaddr $self;

   $self->lock->set( k => $key, async => TRUE ) or return TRUE;

   return $self->call( $key );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Semaphore - Sub class of Routine with semaphore semantics

=head1 Synopsis

   use Async::IPC;

   my $factory = Async::IPC->new( builder => Class::Usul->new );

   my $semaphore = $factory->new_notifier
      (  code => sub { ... code to run in a child process ... },
         desc => 'description used by the logger',
         key  => 'logger key used to identify a log entry',
         type => 'semaphore' );

   my $result = $semaphore->call( @args );

=head1 Description

Sub class of L<Async::IPC::Routine> with semaphore semantics

=head1 Configuration and Environment

Defines no attributes

=head1 Subroutines/Methods

=head2 C<BUILDARGS>

Wraps the code reference. When called it will reset the lock set by the
L</raise> call

=head2 C<raise>

Call the child process, setting a semaphore

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<Moo>

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
