use t::boilerplate;

use Test::More;
use Test::Requires { 'Linux::Inotify2' => 1.22 };
use Class::Usul::Functions qw( nonblocking_write_pipe_pair );
use Class::Usul::Programs;
use File::DataClass::IO qw( io );

use_ok 'Async::IPC';

my $prog     =  Class::Usul::Programs->new
   (  config => { appclass => 'Class::Usul', tempdir => 't' }, noask => 1, );
my $factory  =  Async::IPC->new( builder => $prog );
my $loop     =  $factory->loop;
my $log      =  $prog->log;

$prog->config->logfile->exists and $prog->config->logfile->unlink;

sub wait_for (&) {
   my ($cond) = @_;
   my (undef, $callerfile, $callerline) = caller;
   my $timedout = 0;

   $loop->watch_time(my $timerid = $loop->uuid, sub { $timedout = 1 }, 10);

   $loop->once(1) while (!$cond->() && !$timedout);

   if ($timedout) {
      die "Nothing was ready after 10 second wait; called at $callerfile "
        . "line $callerline\n";
   }
   else { $loop->unwatch_time($timerid) }
}

my $found = 0;
my $lost  = 0;
my $size  = 0;
my $path  = io['t', 'dummy'];

$path->unlink if $path->exists;

my $file  = $factory->new_notifier(
   type     => 'file',
   desc     => 'the file test notifier',
   interval => 0.5,
   name     => 'file1',
   path     => $path,
   on_size_changed => sub { $size = $_[2] },
   on_stat_changed => sub {
      $found = 1 if !$_[1] &&  $_[2];
      $lost  = 1 if  $_[1] && !$_[2];
   },
);

$loop->once;
is $found, 0, 'File not found';
$path->touch; wait_for { $found };
is $found, 1, 'File found';
is $lost,  0, 'File not lost';
is $size,  0, 'File size zero';
$path->print( 'xxx' )->flush; wait_for { $size };
is $lost,  0, 'File still not lost';
is $size,  3, 'File size non zero';
$path->exists and $path->close->unlink; wait_for { $lost };
is $lost,  1, 'File lost';
undef $file;

my $called = 0; my $count = 0;

my ($rdr, $wtr) = @{ nonblocking_write_pipe_pair() };

# This breaks if the interval is too small < 3
SKIP: {
   $ENV{AUTHOR_TESTING} or skip 'Too fragile', 1;

   $file = $factory->new_notifier(
      type     => 'file',
      desc     => 'the file test notifier',
      handle   => $rdr,
      interval => 3,
      name     => 'file2',
      on_stat_changed => sub { $called++; $count++ },
   );

   $loop->once(1);
   is $called, 0, 'Stat not changed open file handle';
   is $wtr->syswrite('xxx'), 3, 'Writes 3 bytes';
   wait_for { $called }; $called = 0;
   is $count, 1, 'Stat changed open file handle 1';
# Printing three bytes does not work coz the size of the file doesn't change
   is $wtr->syswrite('xxxx'), 4, 'Write 4 bytes';
   wait_for { $called };
   is $count, 2, 'Stat changed open file handle 2';
   undef $file;
}

$called = 0;
$count  = 0;
$path   = io['t', 'inotify_test'];

$path->touch;

$file   = $factory->new_notifier(
   type => 'file',
   desc => 'the file test notifier',
   name => 'file3',
   on_stat_changed => sub { $called++; $count++ },
   path => $path,
);

$loop->once(1);
is $count, 0, 'OS dependent starts zero';
$path->print('xxx')->flush;
wait_for { $called }; $called = 0;
is $count, 1, 'OS dependent notifier 1';
# Printing three bytes does not work coz the size of the file doesn't change
$path->print('xxxx')->flush;
wait_for { $called }; $called = 0;
is $count, 2, 'OS dependent notifier 2';
$path->close->unlink;
wait_for { $called }; $called = 0;
is $count, 3, 'OS dependent notifier 3';
$path->print('xxx')->flush;
wait_for { $called }; $called = 0;
is $count, 4, 'OS dependent notifier 4';
$path->close->unlink;
undef $file;

$prog->config->logfile->unlink unless $prog->debug;
done_testing;
