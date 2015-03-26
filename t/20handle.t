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
             name        => 'log_key',
             loop        => $loop, };

ok exception { Async::IPC::Handle->new( %{ $args } ) }, 'Not a filehandle';

my ($rdr, $wtr) = @{ nonblocking_write_pipe_pair() };

my $readready = 0; my @rrargs; delete $args->{handle};

$args->{read_handle  } = $rdr;
$args->{on_read_ready} = sub { @rrargs = @_; $readready = 1 };

my $handle = Async::IPC::Handle->new( %{ $args } );

ok defined $handle, 'Read handle defined';
isa_ok $handle, 'Async::IPC::Handle', 'Read handle';
is $handle->read_handle, $rdr, 'Read handle is right handle';
is $handle->write_handle, undef, 'Write handle undefined';
ok $handle->want_readready, 'Want readready true';
is $readready, 0, 'Readready while idle';

$wtr->syswrite( "data\n" ); $loop->once;

is $readready, 1, 'Readready while readable';
is $rrargs[ 0 ], $handle, 'Read ready args while readable';

$rdr->getline; $readready = 0;

ok exception { $handle->want_writeready( 1 ); },
   'Setting want_writeready with write_handle == undef dies';

$handle->close; ($rdr, $wtr) = @{ nonblocking_write_pipe_pair() };

my $writeready = 0; my @wrargs;

delete $args->{read_handle}; delete $args->{on_read_ready};

$args->{name          } = 'log_key2';
$args->{write_handle  } = $wtr;
$args->{on_write_ready} = sub { @wrargs = @_; $writeready = 1 };

$handle = Async::IPC::Handle->new( %{ $args } );

ok defined $handle, 'Write handle defined';
isa_ok $handle, 'Async::IPC::Handle', 'Write handle';
is $handle->write_handle, $wtr, 'Write handle is right handle';
is $handle->read_handle, undef, 'Read handle undefined';
ok $handle->want_writeready, 'Want writeready true';
is $writeready, 0, 'Writeready while idle';
$loop->once;
$handle->want_writeready( 1 );
$loop->once;
is $writeready, 1, 'Writeready while writeable';
is $wrargs[ 0 ], $handle, 'Write ready args while writeable';
$prog->debug or $prog->config->logfile->unlink;

done_testing;
