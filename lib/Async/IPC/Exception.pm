package Async::IPC::Exception;

use namespace::autoclean;

use Unexpected::Functions qw( has_exception );
use Unexpected::Types     qw( Int Str );
use Moo;

extends q(Unexpected);
with    q(Unexpected::TraitFor::ErrorLeader);
with    q(Unexpected::TraitFor::ExceptionClasses);

my $class = __PACKAGE__;

$class->ignore_class( 'Sub::Quote' );

has_exception $class;

has_exception 'Tainted' => parents => [ $class ],
   error => 'String [_1] contains possible taint'
   unless $class->is_exception('Tainted');

has '+class' => default => $class;

has 'out'    => is => 'ro', isa => Str, default => q();

has 'rv'     => is => 'ro', isa => Int, default => 1;

has 'time'   => is => 'ro', isa => Int, default => CORE::time(),
   init_arg  => undef;

1;
