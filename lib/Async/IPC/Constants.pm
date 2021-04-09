package Async::IPC::Constants;

use strict;
use warnings;
use parent 'Exporter::Tiny';

use Async::IPC::Exception;
use File::DataClass::Constants ();

my $exception_class = 'Async::IPC::Exception';

File::DataClass::Constants->Exception_Class($exception_class);

sub Exception_Class {
   my ($self, $class) = @_;

   return $exception_class unless defined $class;

   $exception_class->throw(
      "Exception class ${class} is not loaded or has no throw method"
   ) unless $class->can('throw');

   return $exception_class = $class;
}

my $log_key_width = 15;

sub Log_Key_Width {
   my ($self, $v) = @_;

   return $log_key_width unless defined $v;

   return $log_key_width = $v;
}

our @EXPORT = qw( DEFAULT_ENCODING EXCEPTION_CLASS FALSE
                  LOG_KEY_WIDTH NUL OK SPC TRUE UNTAINT_CMDLINE );

sub FALSE () { 0    }
sub NUL   () { q()  }
sub OK    () { 0    }
sub SPC   () { q( ) }
sub TRUE  () { 1    }

sub DEFAULT_ENCODING () { 'UTF-8' }
sub EXCEPTION_CLASS  () { __PACKAGE__->Exception_Class }
sub LOG_KEY_WIDTH    () { __PACKAGE__->Log_Key_Width }
sub UNTAINT_CMDLINE  () { qr{ \A ([^\$&;<>\`|]+) \z }mx }

1;
