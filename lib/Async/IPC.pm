package Async::IPC;

use 5.010001;
use namespace::autoclean;
use version; our $VERSION = qv( sprintf '0.1.%d', q$Rev: 8 $ =~ /\d+/gmx );

use Moo;
use Async::IPC::Functions  qw( log_leader );
use Async::IPC::Loop;
use Class::Usul::Constants qw( TRUE );
use Class::Usul::Functions qw( ensure_class_loaded first_char );
use Class::Usul::Types     qw( BaseType Object );
use POSIX                  qw( WEXITSTATUS );

# Public attributes
has 'loop'  => is => 'lazy', isa => Object,
   builder  => sub { Async::IPC::Loop->new };

# Private attributes
has '_usul' => is => 'ro',   isa => BaseType, handles => [ 'log' ],
   init_arg => 'builder', required => TRUE;

# Public methods
sub new_notifier {
   my ($self, %p) = @_;

   my $desc = delete $p{desc}; my $log = $self->log; my $key = delete $p{key};

   my $log_level = delete $p{log_level} || 'info'; my $type = delete $p{type};

   my $logger = sub {
      my ($level, $id, $msg) = @_; my $lead = log_leader $level, $key, $id;

      return $log->$level( $lead.$msg );
   };

   my $_on_exit = delete $p{on_exit}; my $on_exit = sub {
      my $pid = shift; my $rv = WEXITSTATUS( shift );

      $logger->( $log_level, $pid, ucfirst "${desc} stopped rv ${rv}" );

      return $_on_exit ? $_on_exit->( $pid, $rv ) : undef;
   };

   my $class = first_char $type eq '+' ? (substr $type, 1)
                                       : __PACKAGE__.'::'.(ucfirst $type);

   ensure_class_loaded $class;

   my $notifier = $class->new( builder     => $self->_usul,
                               description => $desc,
                               log_key     => $key,
                               loop        => $self->loop,
                               on_exit     => $on_exit, %p, );

   $desc = $notifier->description;
   $logger->( $log_level, $notifier->pid, "Started ${desc}" );
   return $notifier;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC - Asyncronous inter process communication

=head1 Synopsis

   use Async::IPC;

   my $factory = Async::IPC->new( builder => Class::Usul->new );

   my $notifier = $factory->new_notifier
      (  code => sub { ... code to run in a child process ... },
         desc => 'description used by the logger',
         key  => 'logger key used to identify a log entry',
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

A required instance of L<Class::Usul>

=item C<loop>

An instance of L<Async::IPC::Loop>. Created by the constructor

=back

=head1 Subroutines/Methods

=head2 C<new_notifier>

Returns an object reference for a newly instantiated instance of a notifier
class. The notifier types and their classes are;

=over 3

=item C<function>

An instance of L<Async::IPC::Function>

=item C<periodical>

An instance of L<Async::IPC::Periodical>

=item C<process>

An instance of L<Async::IPC::Process>

=item C<routine>

An instance of L<Async::IPC::Routine>

=item C<semaphore>

An instance of L<Async::IPC::Semaphore>

=back

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
