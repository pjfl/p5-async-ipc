use t::boilerplate;

use Test::More;
use Class::Usul::Programs;
use English qw( -no_match_vars );

use_ok 'Async::IPC';

my $prog     =  Class::Usul::Programs->new
   (  config => { appclass => 'Class::Usul', tempdir => 't' }, noask => 1, );
my $factory  =  Async::IPC->new( builder => $prog );
my $loop     =  $factory->loop;
my $log      =  $prog->log;

my $count = 0;

my $id = $loop->watch_signal( USR1 => sub { $count++ } );

kill 'USR1', $PID;
is $count, 0, 'Count zero';
$loop->once;
is $count, 1, 'Traps USR1';
kill 'USR1', $PID; $loop->once;
is $count, 2, 'Traps USR1 again';
is $loop->watching_signal( 'USR1', $id ), 1, 'Is watching USR1';
$loop->unwatch_signal( 'USR1', $id );
is $loop->watching_signal( 'USR1', $id ), 0, 'Not watching USR1';

done_testing;
