use t::boilerplate;

use Test::More;
use Class::Usul::Programs;
use Class::Usul::Functions qw( sum );

use_ok 'Async::IPC';

my $prog        =  Class::Usul::Programs->new
   (  config    => { appclass => 'Class::Usul', tempdir => 't' }, noask => 1, );
my $factory     =  Async::IPC->new( builder => $prog );
my $loop        =  $factory->loop;
my $log         =  $prog->log;

my $count       =  0;
my $max_calls   =  3;
my $results     =  {};
my $semaphore   =  $factory->new_notifier
   (  code      => sub { $count >= $max_calls and $loop->stop; $count++ },
      desc      => 'description',
      max_calls => $max_calls,
      name      => 'key',
      on_exit   => sub { $loop->stop },
      on_return => sub { $results->{ $count++ } = $_[ 1 ] },
      type      => 'semaphore' );
my $timer       =  $factory->new_notifier
   (  code      => sub { $semaphore->raise },
      desc      => 'description',
      interval  => 1,
      name      => 'key',
      type      => 'periodical', );

my $id = $loop->watch_signal( INT => sub { $loop->stop } );

$loop->start; $timer->stop; $semaphore->stop;

$loop->unwatch_signal( INT => $id );

for (sort { $a <=> $b } keys %{ $results }) {
   is $results->{ $_ }, $_, "raise ${_}";
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
