use t::boilerplate;

use Test::More;
use Test::Fatal;
use Class::Usul::Functions qw( nonblocking_write_pipe_pair );
use Class::Usul::Programs;
use IO::Handle;

use_ok 'Async::IPC';

my $prog     =  Class::Usul::Programs->new
   (  config => { appclass => 'Class::Usul', tempdir => 't' }, noask => 1, );
my $factory  =  Async::IPC->new( builder => $prog );
my $loop     =  $factory->loop;
my $log      =  $prog->log;

use_ok 'Async::IPC::Handle';

my $args = { builder     => $prog,
             description => 'description',
             handle      => 'Hello',
             log_key     => 'log_key',
             loop        => $loop, };

ok exception { Async::IPC::Handle->new( %{ $args } ) }, 'Not a filehandle';

my $pair = nonblocking_write_pipe_pair;
my $rdr  = IO::Handle->new_from_fd( $pair->[ 0 ], 'r' );
my $wtr  = IO::Handle->new_from_fd( $pair->[ 1 ], 'w' );

my $readready = 0; my @rrargs; delete $args->{handle};

$args->{read_handle  } = $rdr;
$args->{on_read_ready} = sub { @rrargs = @_; $readready = 1 };

my $handle = Async::IPC::Handle->new( %{ $args } );

ok defined $handle, 'Handle defined';
isa_ok $handle, 'Async::IPC::Handle', 'Handle';
is $handle->read_handle, $rdr, 'Read handle defined';
is $handle->write_handle, undef, 'Write handle undefined';
ok $handle->want_readready, 'Want readready true';
is $readready, 0, 'Readready while idle';

$wtr->syswrite( "data\n" ); $loop->once;

is $readready, 1, 'Readready while readable';
is $rrargs[ 0 ], $handle, 'Read ready args while readable';

$rdr->getline; $readready = 0;

ok exception { $handle->want_writeready( 1 ); },
   'Setting want_writeready with write_handle == undef dies';

done_testing;
