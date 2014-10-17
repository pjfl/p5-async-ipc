package Async::IPC::Base;

use namespace::autoclean;

use Moo;
use Class::Usul::Constants qw( TRUE );
use Class::Usul::Types     qw( BaseType Bool NonEmptySimpleStr
                               NonZeroPositiveInt Object );

has 'autostart'   => is => 'ro',   isa => Bool, default => TRUE;

has 'builder'     => is => 'ro',   isa => BaseType,
   handles        => [ qw( config debug lock log run_cmd ) ],
   required       => TRUE;

has 'description' => is => 'ro',   isa => NonEmptySimpleStr, required => TRUE;

has 'log_key'     => is => 'ro',   isa => NonEmptySimpleStr, required => TRUE;

has 'loop'        => is => 'ro',   isa => Object,            required => TRUE;

has 'pid'         => is => 'lazy', isa => NonZeroPositiveInt;

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Base - One-line description of the modules purpose

=head1 Synopsis

   use Async::IPC::Base;
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