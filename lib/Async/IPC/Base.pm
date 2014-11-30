package Async::IPC::Base;

use namespace::autoclean;

use Moo;
use Class::Usul::Constants qw( TRUE );
use Class::Usul::Types     qw( BaseType Bool NonEmptySimpleStr
                               NonZeroPositiveInt Object );

# Public attributes
has 'autostart'   => is => 'ro',   isa => Bool, default => TRUE;

has 'description' => is => 'ro',   isa => NonEmptySimpleStr, required => TRUE;

has 'log_key'     => is => 'ro',   isa => NonEmptySimpleStr, required => TRUE;

has 'loop'        => is => 'rwp',  isa => Object,            required => TRUE;

has 'pid'         => is => 'lazy', isa => NonZeroPositiveInt;

# Private attributes
has '_usul'       => is => 'ro',   isa => BaseType,
   handles        => [ qw( config debug lock log run_cmd ) ],
   init_arg       => 'builder', required => TRUE;

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Base - Attributes common to each of the notifier classes

=head1 Synopsis

   use Moo;

   extends q(Async::IPC::Base);

=head1 Description

Base class for notifiers

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<autostart>

Read only boolean defaults to true. If false child process creation is delayed
until first use

=item C<description>

A required, immutable, non empty simple string. The description used by the
logger

=item C<log_key>

A required, immutable, non empty simple string. Logger key used to identify a
log entry

=item C<loop>

An instance of L<Async::IPC::Loop>

=item C<pid>

A non zero positive integer. The process id of this notifier

=back

=head1 Subroutines/Methods

None

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
