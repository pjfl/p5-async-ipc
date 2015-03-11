package Async::IPC::Functions;

use strictures;
use parent 'Exporter::Tiny';

use Class::Usul::Constants qw( FAILED FALSE LANG NUL OK SPC TRUE );
use Class::Usul::Functions qw( pad );
use English                qw( -no_match_vars );
use Storable               qw( nfreeze );

our @EXPORT_OK = ( qw( log_leader read_error read_exactly terminate ));

# Private functions
my $_padid = sub {
   my $id = shift; $id //= $PID; return pad $id, 5, 0, 'left';
};

my $_padkey = sub {
   my ($level, $key) = @_; my $w = 11 - length $level; $w < 1 and $w = 1;

   return pad uc( $key ), $w, SPC, 'left';
};

# Public functions
sub log_leader ($$;$) {
   my $dkey = $_padkey->( $_[ 0 ], $_[ 1 ] ); my $did = $_padid->( $_[ 2 ] );

   return "${dkey}[${did}]: ";
}

sub read_error ($$) {
   my ($notifier, $red) = @_; my $pid = $notifier->pid;

   my $log = $notifier->log; my $name = $notifier->name;

   unless (defined $red) {
      $log->error( log_leader( 'error', $name, $pid ).$OS_ERROR ); return TRUE;
   }

   unless (length $red) {
      $log->debug( log_leader( 'debug', $name, $pid ).'EOF' ); return TRUE;
   }

   return FALSE;
}

sub read_exactly ($$$) {
   $_[ 1 ] = NUL;

   while ((my $have = length $_[ 1 ]) < $_[ 2 ]) { # Must be sysread NOT read
      my $red = sysread( $_[ 0 ], $_[ 1 ], $_[ 2 ] - $have, $have );

      defined $red or return; $red or return NUL;
   }

   return $_[ 2 ];
}

sub terminate ($) {
   $_[ 0 ]->unwatch_signal( 'QUIT' ); $_[ 0 ]->unwatch_signal( 'TERM' );
   $_[ 0 ]->stop;
   return TRUE;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Functions - Library functions shared by modules in the distribution

=head1 Synopsis

   use Async::IPC::Functions qw( terminate );

   $loop = Async::IPC::Loop->new;

   # Stop watching the QUIT and TERM signal. Stop the event loop
   terminate $loop;

=head1 Description

Library functions shared by modules in the distribution

=head1 Configuration and Environment

Defines no attributes

=head1 Subroutines/Methods

=head2 C<log_leader>

   $leader = log_leader $level, $key, $id;

Returns the leader string for a log message

=head2 C<read_error>

   $bool = read_error $notifier, $bytes_red;

Returns true if there was an error receiving the arguments in a child process
call. Returns false otherwise. Logs the error if one occurs

=head2 C<read_exactly>

   $bytes_red = read_exactly $file_handle, $buffer, $length;

Returns the number of bytes read from the file handle on success. Returns
undefined if there is a read error, returns the null string if nothing is read
The read bytes are appended to the buffer

=head2 C<terminate>

   $bool = terminate $loop_object;

Returns true. Stops listening for the C<QUIT> and C<TERM> signals. Stops the
event loop

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul>

=item L<Exporter::Tiny>

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
