package Async::IPC::Reader;

use namespace::autoclean;

use Async::IPC::Types qw( CodeRef Object Undef );
use Moo;

has 'on_read' => is => 'ro', isa => CodeRef;

has 'future'  => is => 'ro', isa => Object|Undef;

around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_;

   return $args[0] if is_hashref $args[0];

   my $attr  = {};
   my $count = 0;

   for my $name (qw(on_read future)) {
      $attr->{$name} = $args[$count++];
   }

   return $attr;
};

1;
