use t::boilerplate;

use Test::More;
use Class::Usul::Functions qw( nonblocking_write_pipe_pair );
use Class::Usul::Programs;
use File::DataClass::IO qw( io );

use_ok 'Async::IPC';

my $prog     =  Class::Usul::Programs->new
   (  config => { appclass => 'Class::Usul', tempdir => 't' }, noask => 1, );
my $factory  =  Async::IPC->new( builder => $prog );
my $loop     =  $factory->loop;
my $log      =  $prog->log;

my $found    = 0;
my $lost     = 0;
my $size     = 0;
my $path     = io [ 't', 'dummy' ];
my $file     = $factory->new_notifier
   (  desc   => 'description',
      key    => 'key',
      on_size_changed => sub { $size = $_[ 2 ] },
      on_stat_changed => sub {
         not $_[ 1 ] and $_[ 2 ] and $found = 1;
         $_[ 1 ] and not $_[ 2 ] and $lost  = 1;
      },
      path   => $path,
      type   => 'file' );

$loop->once;
is $found, 0, 'File not found';
$path->touch; $loop->once;
is $found, 1, 'File found';
is $lost,  0, 'File not lost';
is $size,  0, 'File size zero';
$path->print( 'xxx' ); $path->close; $loop->once;
is $lost,  0, 'File still not lost';
is $size,  3, 'File size non zero';
$path->exists and $path->unlink; $loop->once;
is $lost,  1, 'File lost';

my $called = 0; my $pair = nonblocking_write_pipe_pair();

$file = $factory->new_notifier
   (  desc   => 'description',
      handle => $pair->[ 0 ],
      key    => 'key',
      on_stat_changed => sub { $called++ },
      type   => 'file' );

$loop->once;
is $called, 0, 'Stat not changed open file handle';
$pair->[ 1 ]->print( 'xxx' ); $loop->once;
is $called, 1, 'Stat changed open file handle 1';
$pair->[ 1 ]->print( 'xxx' ); $loop->once;
is $called, 2, 'Stat changed open file handle 2';

done_testing;

$prog->config->logfile->unlink;
