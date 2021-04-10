use strict;
use warnings;

use Module::Build 0.4004;

my $perl_ver = 5.010001;
my $name     = 'Async-IPC'; $name =~ s{ - }{::}gmx;
my $prereqs  = {
  'build_requires' => {
    'Module::Build' => '0.4004',
    'version' => '0.88'
  },
  'configure_requires' => {
    'Module::Build' => '0.4004',
    'version' => '0.88'
  },
  'requires' => {
    'AnyEvent' => '7.09',
    'Async::Interrupt' => '1.21',
    'EV' => '4.18',
    'Exporter::Tiny' => '0.042',
    'File::DataClass' => 'v0.66.0',
    'Future' => '0.32',
    'List::Util' => '1.42',
    'MIME::Base64' => '3.13',
    'Moo' => '2.000001',
    'Ref::Util' => '0.203',
    'Try::Tiny' => '0.22',
    'Type::Tiny' => '1.000005',
    'Unexpected' => 'v0.40.0',
    'namespace::autoclean' => '0.26',
    'perl' => '5.010001',
    'strictures' => '2.000000'
  },
  'test_requires' => {
    'Class::Usul' => 'v0.84.1',
    'File::Spec' => '0',
    'Module::Build' => '0.4004',
    'Module::Metadata' => '0',
    'Sys::Hostname' => '0',
    'Test::Compile' => 'v1.2.1',
    'Test::Requires' => '0.06',
    'version' => '0.88'
  },
};
my $testing  = sub { $ENV{AUTOMATED_TESTING}
                  || $ENV{PERL_CPAN_REPORTER_CONFIG}
                  || $ENV{PERL5_CPANPLUS_IS_VERSION} };
my $whimper  = sub { print {*STDOUT} $_[ 0 ]."\n"; exit 0 };
my $stop     = sub {
   $testing->() or $whimper->( $_[ 0 ] );
   $prereqs->{build_requires} = { %{ $prereqs->{configure_requires} } };
   $prereqs->{test_requires } = { %{ $prereqs->{configure_requires} } };
   $prereqs->{test_requires }->{ 'Test::Requires' } = 0.06;
   delete $prereqs->{requires};
};
my $osname   = lc $^O; $osname eq 'linux'
   and $prereqs->{requires}->{ 'Linux::Inotify2' } = '1.22';

# Not interested in reports below min perl ver
$] < $perl_ver and $stop->( "Minimum required Perl version is ${perl_ver}" );

Module::Build->new(
   'module_name' => $name,
   'notes'       => { min_perl_version => $perl_ver, testing => $testing->() },
   %{ $prereqs },

)->create_build_script;

exit 0;
