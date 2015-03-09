use t::boilerplate;

use Test::More;
use Class::Usul::Programs;
use Class::Usul::Functions qw( sum );

use_ok 'Async::IPC';

my $prog        =  Class::Usul::Programs->new
   (  config    => { appclass => 'Class::Usul', tempdir => 't' },
      debug     => 1, noask => 1, );
my $factory     =  Async::IPC->new( builder => $prog );
my $loop        =  $factory->loop;
my $log         =  $prog->log;

my $max_calls   =  10;
my $results     =  {};
my $function    =  $factory->new_notifier
   (  desc      => 'the test function notifier',
      name      => 'function_test',
      on_recv   => sub { shift; sum @_ },
      on_return => sub {
         shift; $results->{ $_[ 0 ]->[ 0 ] } = $_[ 0 ]->[ 1 ];
         my $count = () = keys %{ $results };
         $count == $max_calls and $loop->stop },
      type      => 'function' );

for (my $i = 0; $i < $max_calls; $i++) {
   my @args = 1; my $n = 0; while ($n <= $i) { $args[ $n + 1 ] = $n + 2; $n++ }

   $function->call( (sum @args), @args );
}

$loop->start;

for (sort { $a <=> $b } keys %{ $results }) {
   is $results->{ $_ }, $_, "sum ${_}";
}

my $count = () = keys %{ $results };

is $count, $max_calls, 'All results present';
undef $function;

$max_calls   =  11;
$results     =  {};
$function    =  $factory->new_notifier
   (  desc        => 'the test function notifier',
      max_workers => 3,
      name        => 'function_test',
      on_recv     => sub { shift; sum @_ },
      on_return   => sub {
         shift; $results->{ $_[ 0 ]->[ 0 ] } = $_[ 0 ]->[ 1 ];
         my $count = () = keys %{ $results };
         $count == $max_calls and $loop->stop },
      type        => 'function' );

for (my $i = 0; $i < $max_calls; $i++) {
   my @args = 1; my $n = 0; while ($n <= $i) { $args[ $n + 1 ] = $n + 2; $n++ }

   $function->call( (sum @args), @args );
}

$loop->start; $function->stop;

for (sort { $a <=> $b } keys %{ $results }) {
   is $results->{ $_ }, $_, "sum ${_}";
}

$count = () = keys %{ $results };

is $count, $max_calls, 'All results present';

done_testing;

$prog->config->logfile->unlink;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
