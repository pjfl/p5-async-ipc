package Async::IPC::Functions;

use strictures;
use parent 'Exporter::Tiny';

use Class::Usul::Constants qw( FAILED FALSE LANG NUL OK SPC TRUE );
use Class::Usul::Functions qw( pad split_on__ throw );
use English                qw( -no_match_vars );
use Storable               qw( nfreeze );

our @EXPORT_OK = ( qw( log_leader read_exactly recv_arg_error recv_rv_error
                       send_msg terminate ) );

# Public functions
sub log_leader ($$;$) {
   my $dkey = __padkey( $_[ 0 ], $_[ 1 ] ); my $did = __padid( $_[ 2 ] );

   return "${dkey}[${did}]: ";
}

sub read_exactly ($$$) {
   $_[ 1 ] = NUL;

   while ((my $have = length $_[ 1 ]) < $_[ 2 ]) {
      my $red = read( $_[ 0 ], $_[ 1 ], $_[ 2 ] - $have, $have );

      defined $red or return; $red or return NUL;
   }

   return $_[ 2 ];
}

sub recv_arg_error ($$$) {
   return __recv_hndlr( 'RCVARG', @_ );
}

sub recv_rv_error ($$$) {
   return __recv_hndlr( 'RECVRV', @_ );
}

sub send_msg ($$$;@) {
   my ($writer, $log, $key, @args) = @_;

   my $lead = log_leader 'error', $key, $args[ 0 ] ||= $PID;

   $writer or ($log->error( "${lead}No writer" ) and return FALSE);

   my $rec  = nfreeze [ @args ];
   my $buf  = pack( 'I', length $rec ).$rec;
   my $len  = $writer->syswrite( $buf, length $buf );

   defined $len or ($log->error( $lead.$OS_ERROR ) and return FALSE);

   return TRUE;
}

sub terminate ($) {
   $_[ 0 ]->unwatch_signal( 'QUIT' ); $_[ 0 ]->unwatch_signal( 'TERM' );
   $_[ 0 ]->stop;
   return TRUE;
}

# Private functions
sub __padid {
   my $id = shift; $id //= $PID; return pad $id, 5, 0, 'left';
}

sub __padkey {
   my ($level, $key) = @_; my $w = 11 - length $level; $w < 1 and $w = 1;

   return pad $key, $w, SPC, 'left';
}

sub __recv_hndlr {
   my ($key, $log, $id, $red) = @_;

   unless (defined $red) {
      $log->error( log_leader( 'error', $key, $id ).$OS_ERROR ); return TRUE;
   }

   unless (length $red) {
      $log->info( log_leader( 'info', $key, $id ).'EOF' ); return TRUE;
   }

   return FALSE;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

Async::IPC::Functions - One-line description of the modules purpose

=head1 Synopsis

   use Async::IPC::Functions;
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
