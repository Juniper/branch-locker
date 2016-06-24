
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

{
    # These are in addition to the values loaded from branchlocker.pl, also
    # values here override the values in branchlocker.pl when loaded.
    'word'       => 'Offline Mode',
    'broadcasts' => [
        'This is the offline instance of Branch Locker.',
    ],

    # Read only settings, exceptions check for existence of key and not
    # the value held in the key.
    'readonly' => 0,
    'readonly_exceptions' => [
    ],

    # Branch::Locker config.
    'Branch::Locker' => {
        'readwrite_user'   => 'blr_w',
        'readwrite_pass'   => '',
        'readwrite_host'   => 'localhost',

        'readonly_user'    => 'blr_w',
        'readonly_pass'    => '',
        'databases'        => ['branchlocker'],
        'database_servers' => {
            'local' => ['localhost'],
        },
    }
}
