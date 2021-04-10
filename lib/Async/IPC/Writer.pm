package Async::IPC::Writer;

use namespace::autoclean;

use Async::IPC::Constants qw( FALSE );
use Async::IPC::Types     qw( Bool CodeRef Maybe NonZeroPositiveInt
                              Object Str );
use Ref::Util             qw( is_hashref );
use Moo;

has 'data'     => is => 'rw', isa => CodeRef | Object | Str;

has 'writelen' => is => 'ro', isa => NonZeroPositiveInt;

has 'on_write' => is => 'ro', isa => Maybe[CodeRef];

has 'on_flush' => is => 'ro', isa => Maybe[CodeRef];

has 'on_error' => is => 'ro', isa => Maybe[CodeRef];

has 'watching' => is => 'rw', isa => Bool, default => FALSE;

around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_;

   return $args[0] if is_hashref $args[0];

   my $attr  = {};
   my $count = 0;

   for my $name (qw(data writelen on_write on_flush on_error watching)) {
      $attr->{$name} = $args[$count++];
   }

   return $attr;
};

1;
