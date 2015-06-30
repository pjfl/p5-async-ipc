use strict;
use warnings;

use Module::Build 0.4004;

sub testing { $ENV{AUTOMATED_TESTING} || $ENV{PERL_CPAN_REPORTER_CONFIG}
                                      || $ENV{PERL5_CPANPLUS_IS_VERSION} }
sub whimper { print {*STDOUT} $_[ 0 ]."\n"; exit 0 }

my $perl_ver = 5.010001;
my $name     = 'Async-IPC'; $name =~ s{ - }{::}gmx;
my $prereqs  = {
  'build_requires' => {
    'Module::Build' => '0.4004',
    'Test::Compile' => 'v1.2.1',
    'Test::Requires' => '0.06',
    'version' => '0.88'
  },
  'configure_requires' => {
    'Module::Build' => '0.4004',
    'version' => '0.88'
  },
  'requires' => {
    'AnyEvent' => '7.09',
    'Async::Interrupt' => '1.21',
    'Class::Usul' => 'v0.63.0',
    'EV' => '4.18',
    'Exporter::Tiny' => '0.042',
    'File::DataClass' => 'v0.63.0',
    'Future' => '0.32',
    'Moo' => '2.000001',
    'Try::Tiny' => '0.22',
    'Type::Tiny' => '1.000005',
    'Unexpected' => 'v0.38.0',
    'namespace::autoclean' => '0.26',
    'perl' => '5.010001',
    'strictures' => '2.000000'
  },
};
my $osname   = lc $^O; $osname eq 'linux'
   and $prereqs->{requires}->{ 'Linux::Inotify2' } = '1.22';

if ($] < $perl_ver) { # Not interested in reports below min perl ver
   testing or whimper "Minimum required Perl version is ${perl_ver}";
   $prereqs->{build_requires} = { %{ $prereqs->{configure_requires} } };
   $prereqs->{build_requires}->{ 'Test::Requires' } = 0.06;
   delete $prereqs->{requires};
}

Module::Build->new(
   'module_name' => $name,
   'notes'       => { min_perl_version => $perl_ver, testing => testing },
   %{ $prereqs },

)->create_build_script;

exit 0;
