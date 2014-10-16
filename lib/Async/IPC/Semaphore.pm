package Async::IPC::Semaphore;

use namespace::autoclean;

use Moo;
use Class::Usul::Constants qw( FALSE TRUE );
use Class::Usul::Functions qw( arg_list );
use Scalar::Util           qw( refaddr );

extends q(Async::IPC::Routine);

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = arg_list @args;

   my $code = $attr->{code}; my $lock = $attr->{builder}->lock;

   $attr->{code} = sub { $lock->reset( k => $_[ 0 ] ); $code->( @_ ) };

   return $orig->( $self, $attr );
};

sub raise {
   my $self = shift; $self->is_running or return FALSE; my $key = refaddr $self;

   $self->lock->set( k => $key, async => TRUE ) or return TRUE;

   return $self->call( $key );
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Semaphore - One-line description of the modules purpose

=head1 Synopsis

   use Async::IPC::Semaphore;
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
