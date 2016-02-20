use strict;
use warnings;

use BranchLocker;

my $app = BranchLocker->apply_default_middlewares(BranchLocker->psgi_app);
$app;

