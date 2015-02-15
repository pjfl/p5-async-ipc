use t::boilerplate;

use Test::More;
use Class::Usul::Programs;
use File::DataClass::IO qw( io );

use_ok 'Async::IPC';

my $prog        =  Class::Usul::Programs->new
   (  config    => { appclass => 'Class::Usul', tempdir => 't' }, noask => 1, );
my $factory     =  Async::IPC->new( builder => $prog );
my $loop        =  $factory->loop;
my $log         =  $prog->log;

my $found       = 0;
my $path        = io [ 't', 'dummy' ]; $path->exists and $path->unlink;
my $file        = $factory->new_notifier
   (  desc      => 'description',
      key       => 'key',
      on_stat_changed => sub { $found = 1 },
      path      => $path,
      type      => 'file' );

$path->touch; $loop->once;

is $found, 1, 'File found';

done_testing;

$path->exists and $path->unlink;
