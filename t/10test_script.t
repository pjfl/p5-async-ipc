use t::boilerplate;

use Test::More;
use Test::Compile;

my @pms = all_pm_files;

plan tests => @pms + 0;

pm_file_ok( $_ ) for (@pms);

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
