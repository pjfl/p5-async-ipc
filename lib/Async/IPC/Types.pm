package Async::IPC::Types;

use strict;
use warnings;

use Async::IPC::Constants qw( DEFAULT_ENCODING EXCEPTION_CLASS FALSE TRUE );
use Async::IPC::Functions qw( untaint_cmdline );
use Encode                qw( find_encoding );
use Scalar::Util          qw( blessed tainted );
use Try::Tiny;
use Type::Library            -base, -declare =>
                          qw( Builder ConfigProvider DataEncoding );
use Type::Utils           qw( as class_type coerce extends
                              from message subtype via where );
use Unexpected::Functions qw( inflate_message is_class_loaded );

use namespace::clean -except => 'meta';

BEGIN { extends q(Unexpected::Types) };

# Type definitions
subtype Builder, as Object,
   where   { _has_builder_attributes($_) },
   message { _exception_message_for_builder($_) };

subtype ConfigProvider, as Object,
   where   { _has_min_config_attributes($_) },
   message { _exception_message_for_configprovider($_) };

subtype DataEncoding, as Str,
   where   { _isa_untainted_encoding($_) },
   message { inflate_message 'String [_1] is not a valid encoding', $_ };

coerce DataEncoding,
   from Str,   via { untaint_cmdline $_ },
   from Undef, via { DEFAULT_ENCODING };

# Private functions
sub _exception_message_for_builder {
   my $self = shift;

   return _exception_message_for_object_ref($self)
      unless $self && blessed $self;

   return inflate_message
      'Object [_1] is missing some builder attributes', blessed $self;
}

sub _exception_message_for_configprovider {
   my $self = shift;

   return _exception_message_for_object_ref($self)
      unless $self && blessed $self;

   return inflate_message
      'Object [_1] is missing some configuration attributes', blessed $self;
}

sub _exception_message_for_object_ref {
   my $self = shift;

   return inflate_message 'String [_1] is not an object reference', $self;
}

sub _has_builder_attributes {
   my $obj  = shift;
   my @attr = (qw( config debug lock log run_cmd ));

   for (@attr) { return FALSE unless $obj->can($_) }

   return TRUE;
}

sub _has_min_config_attributes {
   my $obj  = shift;
   my @attr = (qw( pathname tempdir ));

   for (@attr) { return FALSE unless $obj->can($_) }

   return TRUE;
}

sub _isa_untainted_encoding {
   my $enc = shift;
   my $res;

   try   { $res = !tainted($enc) and find_encoding($enc) ? TRUE : FALSE }
   catch { $res = FALSE };

   return $res
}

1;
