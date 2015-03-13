use t::boilerplate;

use Test::More;
use Class::Usul::Programs;
use File::Temp qw( tempfile );

use_ok 'Async::IPC';

my $prog        =  Class::Usul::Programs->new
   (  config    => { appclass => 'Class::Usul', tempdir => 't' },
      debug     => 1, noask => 1, );
my $factory     =  Async::IPC->new( builder => $prog );
my $loop        =  $factory->loop;
my $log         =  $prog->log;

sub mkhandles {
   my ($rd, $filename) = tempfile( 'tmpfile.XXXXXX', UNLINK => 1 );

   open my $wr, '>', $filename or die "Cannot reopen file for writing - $!";

   $wr->autoflush( 1 );

   return ($rd, $wr, $filename);
}

sub wait_for (&) {
   my ($cond) = @_; my (undef, $callerfile, $callerline) = caller;

   my $timedout = 0; $loop->watch_time
      ( my $timerid = $loop->uuid, sub { $timedout = 1 }, 10, );

   $loop->once( 1 ) while (not $cond->() and not $timedout);

   $timedout and die "Nothing was ready after 10 second wait; called at $callerfile line $callerline\n";
   $loop->unwatch_time( $timerid );
   return;
}

my @lines; my $initial_size; my ($rdr, $wtr) = mkhandles;

my $filestream = $factory->new_notifier
   (  description => 'the test file stream notifier',
      handle      => $rdr,
      interval    => 1,
      name        => 'filestream',
      on_initial  => sub { ( undef, $initial_size ) = @_ },
      on_read     => sub {
         my ($self, $buffref, $eof) = @_;

         push @lines, $1 while (${ $buffref } =~ s{ \A (.*\n) }{}mx);

         return 0;
      },
      type        => 'fileStream', );

ok defined $filestream, 'Filestream defined';
isa_ok $filestream, 'Async::IPC::FileStream', 'File stream';
is $initial_size, 0, 'Initial size is 0';

$wtr->syswrite( "message\n" );

is_deeply \@lines, [], 'Lines before wait';

wait_for { scalar @lines };

is_deeply \@lines, [ "message\n" ], 'Lines after wait';
$filestream->stop;
$prog->config->logfile->unlink;

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
