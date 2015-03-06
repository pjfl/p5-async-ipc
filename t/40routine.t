use t::boilerplate;

use Test::More;
use Class::Usul::Programs;
use Class::Usul::Functions qw( sum );
use File::DataClass::IO;

use_ok 'Async::IPC';

my $prog        =  Class::Usul::Programs->new
   (  config    => { appclass => 'Class::Usul', tempdir => 't' },
      debug     => 1, noask => 1, );
my $factory     =  Async::IPC->new( builder => $prog );
my $loop        =  $factory->loop;
my $log         =  $prog->log;

my $max_calls   =  10;
my $results     =  {};
my $routine     =  $factory->new_notifier
   (  code      => sub { shift; sum @_ },
      desc      => 'the test routine notifier',
      max_calls => $max_calls,
      name      => 'routine_test',
      on_exit   => sub { $loop->stop },
      on_recv   => sub { shift; $results->{ $_[ 0 ]->[ 0 ] } = $_[ 0 ]->[ 1 ] },
      type      => 'routine' );

for (my $i = 0; $i < $max_calls; $i++) {
   my @args = 1; my $n = 0; while ($n <= $i) { $args[ $n + 1 ] = $n + 2; $n++ }

   $routine->call( (sum @args), @args );
}

$loop->start;

for (sort { $a <=> $b } keys %{ $results }) {
   is $results->{ $_ }, $_, "sum ${_}";
}

my $count = () = keys %{ $results };

is $count, $max_calls, 'All results present';

$prog->config->logfile->unlink;

my $err = io [ 't', 'routine_test.err' ]; $err->exists and $err->unlink;

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
