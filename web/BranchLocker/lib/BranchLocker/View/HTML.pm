
=head1 NAME

BranchLocker::View::HTML - Catalyst TTSite View

=head1 SYNOPSIS

See L<BranchLocker>

=head1 DESCRIPTION

Catalyst TTSite View.

=head1 AUTHOR

Justin Bellomi

=head1 LICENSE

Copyright (c) 2016, Juniper Networks Inc.
All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package BranchLocker::View::HTML;

use strict;
use base 'Catalyst::View::TT';

__PACKAGE__->config({
    INCLUDE_PATH => [
        BranchLocker->path_to('root', 'src'),
        BranchLocker->path_to('root', 'lib')
    ],
    PRE_PROCESS        => 'config/main',
    WRAPPER            => 'site/wrapper',
    ERROR              => 'error.tt2',
    TEMPLATE_EXTENSION => '.tt2',
    TIMER              => 0,
    render_die         => 1,
});

1;

