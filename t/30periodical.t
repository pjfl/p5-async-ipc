use t::boilerplate;

use Test::More;
use Class::Usul::Programs;

use_ok 'Async::IPC';

my $prog     =  Class::Usul::Programs->new
   (  config => { appclass => 'Class::Usul', tempdir => 't' }, noask => 1, );
my $factory  =  Async::IPC->new( builder => $prog );
my $loop     =  $factory->loop;
my $log      =  $prog->log;

my $max_calls  =  3;
my $results    =  {};
my $count      =  0;
my $timer      =  $factory->new_notifier
   (  code     => sub {
         $results->{ $count } = $count; $count++;
         $count == $max_calls and $loop->stop },
      interval => 1,
      desc     => 'description',
      name     => 'key',
      type     => 'periodical' );

$loop->start; $timer->stop;

for (sort { $a <=> $b } keys %{ $results }) {
   is $results->{ $_ }, $_, "count ${_}";
}

$count = () = keys %{ $results };

is $count, $max_calls, 'All results present';
$prog->debug or $prog->config->logfile->unlink;

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
