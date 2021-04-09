package Async::IPC::Functions;

use strictures;
use parent 'Exporter::Tiny';

use Async::IPC::Constants  qw( EXCEPTION_CLASS FALSE LOG_KEY_WIDTH NUL SPC
                               TRUE UNTAINT_CMDLINE );
use Digest::MD5            qw( md5 );
use English                qw( -no_match_vars );
use MIME::Base64           qw( encode_base64url );
use Module::Runtime        qw( is_module_name require_module );
use Ref::Util              qw( is_coderef is_hashref );
use Scalar::Util           qw( blessed );
use Socket                 qw( AF_UNIX SOCK_STREAM PF_UNSPEC );
use Symbol;
use Sys::Hostname          qw( hostname );
use Unexpected::Functions  qw( is_class_loaded Tainted Unspecified );

our @EXPORT_OK = qw( bson64id ensure_class_loaded first_char log_debug
                     log_error log_info log_warn pad read_error read_exactly
                     socket_pair terminate thread_id throw throw_on_error
                     to_hashref untaint_cmdline untaint_string );

my $bson_id_count  = 0;
my $bson_prev_time = 0;
my $host_id        = substr md5(hostname), 0, 3;

# Public functions
sub bson64id (;$) {
   my $now = time;
   my $tm  = (substr pack('N', $now >> 32), 2, 2).(pack 'N', $now % 0xFFFFFFFF);
   my $pid = pack 'n', $PID % 0xFFFF;
   my $tid = pack 'n', thread_id() % 0xFFFF;

   $bson_id_count++;
   $bson_id_count = 0 if $now > $bson_prev_time;
   $bson_prev_time = $now;

   my $inc = pack 'n', $bson_id_count % 0xFFFF;

   return encode_base64url($tm.$host_id.$pid.$tid.$inc);
}

sub ensure_class_loaded ($;$) {
   my ($class, $opts) = @_;

   throw(Unspecified, ['class name'], level => 2) unless $class;

   $opts //= {};

   throw('String [_1] invalid classname', [$class], level => 2)
      unless is_module_name($class);

   return 1 if !$opts->{ignore_loaded} && is_class_loaded($class);

   eval { require_module($class) };

   throw_on_error({ level => 3 });

   throw('Class [_1] loaded but package undefined', [$class], level => 2)
      unless is_class_loaded($class);

   return 1;
}

sub first_char ($) {
   return substr $_[0], 0, 1;
}

sub log_debug ($$;$$) {
   return _logger('debug', @_);
}

sub log_error ($$;$$) {
   return _logger('error', @_);
}

sub log_info ($$;$$) {
   return _logger('info', @_);
}

sub log_warn ($$;$$) {
   return _logger('warn', @_);
}

sub pad ($$;$$) {
   my ($v, $wanted, $str, $direction) = @_;

   my $len = $wanted - length $v;

   return $v unless $len > 0;

   $str = q( ) unless defined $str and length $str;

   my $pad = substr $str x $len, 0, $len;

   return $v.$pad if !$direction || $direction eq 'right';

   return $pad.$v if $direction eq 'left';

   return (substr $pad, 0, int( (length $pad) / 2 )).$v
         .(substr $pad, 0, int( 0.99999999 + (length $pad) / 2 ));
}

sub read_error ($$) {
   my ($notifier, $red) = @_;

   return log_error($notifier, $OS_ERROR) unless defined $red;
   return log_debug($notifier, 'EOF'    ) unless length  $red;
   return FALSE;
}

sub read_exactly ($$$) {
   $_[1] = NUL;

   while ((my $have = length $_[1]) < $_[2]) { # Must be sysread NOT read
      my $red = sysread($_[0], $_[1], $_[2] - $have, $have);

      return unless defined $red;
      return NUL unless $red;
   }

   return $_[2];
}

sub socket_pair () {
   my $rdr = gensym;
   my $wtr = gensym;

   throw($EXTENDED_OS_ERROR)
      unless socketpair($rdr, $wtr, AF_UNIX, SOCK_STREAM, PF_UNSPEC);
   shutdown($rdr, 1);  # No more writing for reader
   shutdown($wtr, 0);  # No more reading for writer

   return [$rdr, $wtr];
}

sub terminate ($) {
   my $loop = shift;

   $loop->unwatch_signal('QUIT');
   $loop->unwatch_signal('TERM');
   $loop->stop;
   return TRUE;
}

sub thread_id () {
   return exists $INC{ 'threads.pm' } ? threads->tid() : 0;
}

sub throw (;@) {
   EXCEPTION_CLASS->throw(@_);
}

sub throw_on_error (;@) {
   EXCEPTION_CLASS->throw_on_error(@_);
}

sub to_hashref (;@) {
   return $_[0] && is_hashref $_[0] ? { %{ $_[0] } }
        : $_[0]                     ? { @_ }
                                    : {};
}

sub untaint_cmdline (;$) {
   return untaint_string(UNTAINT_CMDLINE, $_[0]);
}

sub untaint_string ($;$) {
   my ($regex, $string) = @_;

   return unless defined $string;
   return q() unless length $string;

   my ($untainted) = $string =~ $regex;

   throw Tainted, [$string], level => 3
      unless defined $untainted && $untainted eq $string;

   return $untainted;
}

# Private functions
sub _is_notifier {
   return (blessed $_[0]
           &&      $_[0]->can('log' )
           &&      $_[0]->can('name')
           &&      $_[0]->can('pid' )) ? TRUE : FALSE;
}

sub _log_leader {
   return _padkey($_[0], $_[1]).'['._padid($_[2]).']';
}

sub _logger {
   my $level = shift;
   my ($log, $key, $pid, $msg) = _parse_log_args(@_);

   $log->$level(_log_leader($level, $key, $pid).": ${msg}");

   return TRUE;
}

sub _padid {
   my $id = shift; $id //= $PID; return pad $id, 5, 0, 'left';
}

sub _padkey {
   my ($level, $key) = @_;

   my $w = LOG_KEY_WIDTH - length $level;

   $w = 1 if $w < 1;

   return pad uc($key), $w, SPC, 'left';
}

sub _parse_log_args {
   my $x = shift;

   return (_is_notifier($x)) ? ($x->log, $x->name, $x->pid, @_)
        : (  is_coderef $x ) ? ($x->(), @_)
                             : ($x, @_);
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
