package Async::IPC::Future;

use strictures;
use parent 'Future';

use Class::Usul::Functions qw( throw );

sub new {
   my $proto = shift; my $self = $proto->SUPER::new;

   if (ref $proto) { $self->{loop} = $proto->{loop} }
   else { $self->{loop} = shift }

   return $self;
}

sub loop {
   return $_[ 0 ]->{loop};
}

sub await {
   my $self = shift; $self->loop->once( @_ ); return;
}

sub done_later {
   my ($self, @result) = @_;

   $self->loop->watch_idle( $self->loop->uuid, sub { $self->done( @result ) } );

   return $self;
}

sub fail_later {
   my ($self, $exception, @details) = @_; my $id = $self->loop->uuid;

   $exception or throw 'Expected a true exception';

   $self->loop->watch_idle( $id, sub { $self->fail( $exception, @details ) } );

   return $self;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Future - Asyncronous inter process communication

=head1 Synopsis

   use Async::IPC::Future;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<loop>

=back

=head1 Subroutines/Methods

=head2 C<new>

=head2 C<await>

=head2 C<done_later>

=head2 C<fail_later>

=head1 Diagnostics

None

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

Copyright (c) 2015 Peter Flanigan. All rights reserved

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
