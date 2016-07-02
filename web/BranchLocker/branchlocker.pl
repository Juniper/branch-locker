
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
    'name'       => 'BranchLocker',
    'domain'     => 'example.com',
    'word'       => 'Default',
    #'broadcasts' => [
    #    'Some Message.'
    #],

    # Read only settings, exceptions check for existence of key and not
    # the value held in the key.
    'readonly' => 0,
    'readonly_exceptions' => [
    ],

    'gui_api_key' => 'Super Secret GUI API Key',
    'gate_keeper_admin_email' => 'gatekeeper-admin@example.com',

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
    },

    'group_order' => [
        'Production',
        'Service',
        'Development',
        'Integration',
    ],
    'group_mapping' => {
        'Production'  => ['Production', 'Feature', 'Release'],
        'Service'     => ['Service', 'Exception'],
        'Development' => ['Development'],
        'Integration' => ['Integration'],
     },
}
