package Async::IPC;

use 5.010001;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 37 $ =~ /\d+/gmx );

use Async::IPC::Constants qw( EXCEPTION_CLASS TRUE );
use Async::IPC::Functions qw( ensure_class_loaded first_char throw to_hashref );
use Async::IPC::Loop;
use Async::IPC::Types     qw( Builder Object );
use Unexpected::Functions qw( Unspecified );
use Moo;

=pod

=encoding utf-8

=begin html

<a href="https://travis-ci.org/pjfl/p5-async-ipc"><img src="https://travis-ci.org/pjfl/p5-async-ipc.svg?branch=master" alt="Travis CI Badge"></a>

=end html

=head1 Name

Async::IPC - Asyncronous inter process communication

=head1 Synopsis

   use Async::IPC;

   my $factory = Async::IPC->new( builder => Class::Usul->new );

   my $notifier = $factory->new_notifier
      (  code => sub { ... code to run in a child process ... },
         desc => 'description used by the logger',
         name => 'logger key used to identify a log entry',
         type => 'routine' );

=head1 Description

A callback style API implemented on L<AnyEvent>

I couldn't make L<IO::Async> work with L<AnyEvent> and L<EV> so this instead

This module implements a factory pattern. It creates instances of the
notifier classes

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=item C<builder>

A required instance of L<Class::Usul>. Dependency injection

=cut

has 'builder' => is => 'ro', isa => Builder, required => TRUE;

=item C<loop>

An instance of L<Async::IPC::Loop>. Created by the constructor

=cut

has 'loop' => is => 'lazy', isa => Object, builder => sub {
   return Async::IPC::Loop->new( builder => $_[0]->builder );
};

=back

=head1 Subroutines/Methods

=head2 C<new_notifier>

Returns an object reference for a newly instantiated instance of a notifier
class. The notifier types and their classes are;

=over 3

=item C<channel>

An instance of L<Async::IPC::Channel>

=item C<file>

An instance of L<Async::IPC::File>

=item C<function>

An instance of L<Async::IPC::Function>

=item C<handle>

An instance of L<Async::IPC::Handle>

=item C<periodical>

An instance of L<Async::IPC::Periodical>

=item C<process>

An instance of L<Async::IPC::Process>

=item C<routine>

An instance of L<Async::IPC::Routine>

=item C<semaphore>

An instance of L<Async::IPC::Semaphore>

=item C<stream>

An instance of L<Async::IPC::Stream>

=back

=cut

sub new_notifier {
   my ($self, @args) = @_;

   my $args  = to_hashref @args;
   my $type  = $args->{type} or throw Unspecified, ['type'];
   my $class = first_char $type eq '+' ? ($args->{type} = substr $type, 1)
                                       : __PACKAGE__ . '::' . (ucfirst $type);

   ensure_class_loaded $class;

   $args->{builder} //= $self->builder;
   $args->{loop} //= $self->loop;

   return $class->new($args);
}

=head2 C<new_future>

Returns an instance of L<Async::IPC::Future>

=cut

sub new_future {
   my $self = shift;

   ensure_class_loaded 'Async::IPC::Future';

   return Async::IPC::Future->new($self);
}

1;

__END__

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<Moo>

=item L<POSIX>

=back

=head1 Incompatibilities

This module revolves around forking processes. Unless it developed a thread
model it won't work on C<mswin32>

=head1 Bugs and Limitations

There are no known bugs in this module. Please report problems to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=Async-IPC.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 Author

Peter Flanigan, C<< <pjfl@cpan.org> >>

=head1 License and Copyright

Copyright (c) 2021 Peter Flanigan. All rights reserved

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
