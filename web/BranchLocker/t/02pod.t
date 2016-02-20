#!/usr/bin/perl

# 2016-01-20 - The above line was changed to #!/usr/bin/perl
#     - justinb@juniper.net

# Copyright (c) 2016, Juniper Networks Inc.
# All rights reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;
use Test::More;

# 2016-01-20 - Changed the unless to negated if statement.  This is just a
# preference.
#     - justinb@juniper.net

plan skip_all => 'set TEST_POD to enable this test' if (! $ENV{TEST_POD});

# End Changes
eval "use Test::Pod 1.14";
plan skip_all => 'Test::Pod 1.14 required' if $@;

all_pod_files_ok();
