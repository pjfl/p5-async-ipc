use t::boilerplate;

use Test::More;
use Class::Usul::Programs;
use Class::Usul::Functions qw( sum );
use File::DataClass::IO;

use_ok 'Async::IPC';

my $prog;

{  package TestLog;

   use Moo;

   sub log {
      my ($self, $level, $msg) = @_;

      $prog->debug and CORE::warn "[${level}]: ${msg}\n";
      return 1;
   }
   sub debug { $_[ 0 ]->log( 'debug', $_[ 1 ] ) }
   sub warn  { $_[ 0 ]->log( 'warn',  $_[ 1 ] ) }
   sub info  { $_[ 0 ]->log( 'info',  $_[ 1 ] ) }
   sub error { $_[ 0 ]->log( 'error', $_[ 1 ] ) }
   sub alert { $_[ 0 ]->log( 'alert', $_[ 1 ] ) }
   sub fatal { $_[ 0 ]->log( 'fatal', $_[ 1 ] ) }
}

$prog = Class::Usul::Programs->new
   (  config    => { appclass => 'Class::Usul', tempdir => 't' },
      log_class => 'TestLog',
      noask     => 1, );
my $factory = Async::IPC->new( builder => $prog );
my $loop    = $factory->loop;

$prog->config->logfile->exists and $prog->config->logfile->unlink;

my $max_calls   =  10;
my $results     =  {};
my $routine     =  $factory->new_notifier
   (  type      => 'routine',
      desc      => 'the test routine notifier',
      name      => 'routine1',
      max_calls => $max_calls,
      on_exit   => sub { $loop->stop },
      on_recv   => sub { shift; shift; sum @_ },
      on_return => sub {
         my ($self, $args) = @_;
         $results->{ $args->[0] } = $args->[1];
         return 1;
      }, );

for (my $i = 0; $i < $max_calls; $i++) {
   my @args = 1; my $n = 0; while ($n <= $i) { $args[ $n + 1 ] = $n + 2; $n++ }

   $routine->call( (sum @args), @args );
}

$loop->start;

for (sort { $a <=> $b } keys %{ $results }) {
   is $results->{ $_ }, $_, "Sync sum ${_}";
}

my $count = () = keys %{ $results };

is $count, $max_calls, 'All sync results present';
undef $routine;

my $after  = io [ 't', 'after'  ]; $after->exists  and $after->unlink;
my $before = io [ 't', 'before' ]; $before->exists and $before->unlink;

$results =  {};
$routine =  $factory->new_notifier
   (  type         => 'routine',
      desc         => 'the test routine notifier',
      name         => 'routine2',
      call_ch_mode => 'async',
      max_calls    => $max_calls,
      after        => sub { $after->touch },
      before       => sub { $before->touch },
      on_exit      => sub { $loop->stop },
      on_recv      => sub { shift; shift; sum @_ },
      on_return    => sub {
         my $self = shift; $results->{ $_[ 0 ]->[ 0 ] } = $_[ 0 ]->[ 1 ];
         return 1 }, );

ok !$after->exists, 'Has not called after';

for (my $i = 0; $i < $max_calls; $i++) {
   my @args = 1; my $n = 0; while ($n <= $i) { $args[ $n + 1 ] = $n + 2; $n++ }

   $routine->call( (sum @args), @args );
}

$loop->start;

ok $before->exists, 'Calls before'; $before->exists and $before->unlink;
ok $after->exists,  'Calls after';  $after->exists  and $after->unlink;

for (sort { $a <=> $b } keys %{ $results }) {
   is $results->{ $_ }, $_, "Async sum ${_}";
}

$count = () = keys %{ $results };

is $count, $max_calls, 'All async results present';
undef $routine;

done_testing;

my $err = io [ 't', 'routine_test.err' ];

$err->exists and not $prog->debug and $err->unlink;
$err->exists and $prog->debug and warn $err->all;
$prog->debug or  $prog->config->logfile->unlink;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
