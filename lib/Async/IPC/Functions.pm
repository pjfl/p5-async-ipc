package Async::IPC::Functions;

use strictures;
use parent 'Exporter::Tiny';

use Class::Usul::Constants qw( FALSE NUL SPC TRUE );
use Class::Usul::Functions qw( is_coderef pad );
use English                qw( -no_match_vars );
use Scalar::Util           qw( blessed );

our @EXPORT_OK = qw( log_debug log_error log_info log_warn
                     read_error read_exactly terminate );

my $Log_Key_Width = 15;

# Private functions
my $_is_notifier = sub {
   return (blessed $_[ 0 ]
           &&      $_[ 0 ]->can( 'log'  )
           &&      $_[ 0 ]->can( 'name' )
           &&      $_[ 0 ]->can( 'pid'  )) ? TRUE : FALSE;
};

my $_padid = sub {
   my $id = shift; $id //= $PID; return pad $id, 5, 0, 'left';
};

my $_padkey = sub {
   my ($level, $key) = @_;

   my $w = $Log_Key_Width - length $level; $w < 1 and $w = 1;

   return pad uc( $key ), $w, SPC, 'left';
};

my $_parse_log_args = sub {
   my $x = shift;

   return ($_is_notifier->( $x )) ? ($x->log, $x->name, $x->pid, @_)
        : (      is_coderef $x  ) ? ($x->(), @_)
                                  : ($x, @_);
};

my $_log_leader = sub {
   return $_padkey->( $_[ 0 ], $_[ 1 ] ).'['.$_padid->( $_[ 2 ] ).']';
};

my $_logger = sub {
   my $level = shift; my ($log, $key, $pid, $msg) = $_parse_log_args->( @_ );

   $log->$level( $_log_leader->( $level, $key, $pid ).": ${msg}" );
   return TRUE;
};

# Class methods
sub log_key_width {
   my ($self, $v) = @_; defined $v or return $Log_Key_Width;

   return $Log_Key_Width = $v;
}

# Public functions
sub log_debug ($$;$$) {
   return $_logger->( 'debug', @_ );
}

sub log_error ($$;$$) {
   return $_logger->( 'error', @_ );
}

sub log_info ($$;$$) {
   return $_logger->( 'info', @_ );
}

sub log_warn ($$;$$) {
   return $_logger->( 'warn', @_ );
}

sub read_error ($$) {
   my ($notifier, $red) = @_;

   not defined $red and return log_error( $notifier, $OS_ERROR );
   not length  $red and return log_debug( $notifier, 'EOF'     );

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
   my $loop = shift;

   $loop->unwatch_signal( 'QUIT' ); $loop->unwatch_signal( 'TERM' );
   $loop->stop;
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

=head2 C<log_debug>

   log_debug $invocant, $message;

Logs the message at the debug level. The C<$invocant> should be a object
reference with C<name> and C<pid> attributes

=head2 C<log_error>

   log_error $invocant, $message;

Logs the message at the error level. The C<$invocant> should be a object
reference with C<name> and C<pid> attributes

=head2 C<log_info>

   log_info $invocant, $message;

Logs the message at the info level. The C<$invocant> should be a object
reference with C<name> and C<pid> attributes

=head2 C<log_warn>

   log_warn $invocant, $message;

Logs the message at the warn level. The C<$invocant> should be a object
reference with C<name> and C<pid> attributes

=head2 C<log_key_width>

   $value = $self->log_key_width( $value );

Class method. Accessor / mutator for the constant width used by the log message
formatting subroutine

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

Copyright (c) 2016 Peter Flanigan. All rights reserved

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
