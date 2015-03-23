use t::boilerplate;

use Test::More;
use Class::Usul::Programs;
use Class::Usul::Time qw( nap );

use_ok 'Async::IPC';

my $prog     =  Class::Usul::Programs->new
   (  config => { appclass => 'Class::Usul', tempdir => 't' }, noask => 1, );
my $factory  =  Async::IPC->new( builder => $prog );
my $loop     =  $factory->loop;
my $log      =  $prog->log;

$prog->config->logfile->exists and $prog->config->logfile->unlink;

my $count       =  0;
my $raised      =  0;
my $max_calls   =  10;
my $results     =  {};
my $semaphore   =  $factory->new_notifier
   (  type      => 'semaphore',
      desc      => 'semaphore test notifier',
      max_calls => $max_calls,
      name      => 'semaphore',
      on_recv   => sub { nap 0.25; $count++ },
      on_return => sub {
         shift; my $ncalls = keys %{ $results };
         $results->{ $ncalls } = $_[ 0 ]->[ 1 ];
         $ncalls >= $max_calls - 1 and $loop->stop }, );
my $timer       =  $factory->new_notifier
   (  type      => 'periodical',
      code      => sub { $raised++; $semaphore->raise },
      desc      => 'semaphore test pump',
      interval  => 0.1,
      name      => 'pump', );

my $id = $loop->watch_signal( INT => sub { $loop->stop } );

$loop->start; $timer->stop; $semaphore->stop;
$loop->unwatch_signal( INT => $id );

for (sort { $a <=> $b } keys %{ $results }) {
   is $results->{ $_ }, $_, "Count ${_}";
}

$count = () = keys %{ $results };

is $count, $max_calls, 'All results present';
ok $raised > $count, "Raises more than count ${raised}";
ok $prog->config->logfile->exists, 'Creates logfile';
$prog->debug or $prog->config->logfile->unlink;

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
