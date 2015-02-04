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

my $max_calls   =  10;
my $results     =  {};
my $routine     =  $factory->new_notifier
   (  code      => sub { shift; sum @_ },
      desc      => 'description',
      key       => 'key',
      max_calls => $max_calls,
      on_exit   => sub { $loop->stop },
      on_return => sub { $results->{ $_[ 0 ] } = $_[ 1 ] },
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

done_testing;

$prog->config->logfile->unlink;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
