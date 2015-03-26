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

sub wait_for (&) {
   my ($cond) = @_; my (undef, $callerfile, $callerline) = caller;

   my $timedout = 0; $loop->watch_time
      ( my $timerid = $loop->uuid, sub { $timedout = 1 }, 10, );

   $loop->once( 1 ) while (not $cond->() and not $timedout);

   if ($timedout) {
      die "Nothing was ready after 10 second wait; called at $callerfile line $callerline\n";
   }
   else { $loop->unwatch_time( $timerid ) }
}

my $found    = 0;
my $lost     = 0;
my $size     = 0;
my $path     = io [ 't', 'dummy' ];
my $file     = $factory->new_notifier
   (  desc   => 'the file test notifier',
      name   => 'file',
      on_size_changed => sub { $size = $_[ 2 ] },
      on_stat_changed => sub {
         not $_[ 1 ] and $_[ 2 ] and $found = 1;
         $_[ 1 ] and not $_[ 2 ] and $lost  = 1;
      },
      path   => $path,
      type   => 'file' );

$loop->once;
is $found, 0, 'File not found';
$path->touch; wait_for { $found };
is $found, 1, 'File found';
is $lost,  0, 'File not lost';
is $size,  0, 'File size zero';
$path->print( 'xxx' ); $path->close; wait_for { $size };
is $lost,  0, 'File still not lost';
is $size,  3, 'File size non zero';
$path->exists and $path->unlink; wait_for { $lost };
is $lost,  1, 'File lost';
undef $file;

my $called = 0; my $count = 0;

my ($rdr, $wtr) = @{ nonblocking_write_pipe_pair() };

$file = $factory->new_notifier
   (  desc   => 'the file test notifier',
      handle => $rdr,
      name   => 'file2',
      on_stat_changed => sub { $called++; $count++ },
      type   => 'file' );

$loop->once( 1 );
is $called, 0, 'Stat not changed open file handle';
$wtr->syswrite( 'xxx' ); wait_for { $called }; $called = 0;
is $count, 1, 'Stat changed open file handle 1';
$wtr->syswrite( 'xxx' ); wait_for { $called };
is $count, 2, 'Stat changed open file handle 2';
$prog->debug or $prog->config->logfile->unlink;
undef $file;

done_testing;
