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

# IMPORTANT: if you delete this file your app will not work as
# expected.  You have been warned.
use inc::Module::Install 1.02;
use Module::Install::Catalyst; # Complain loudly if you don't have
                               # Catalyst::Devel installed or haven't said
                               # 'make dist' to create a standalone tarball.

name 'BranchLocker';
all_from 'lib/BranchLocker.pm';

requires 'Catalyst::Runtime'                => '5.90077';
requires 'Catalyst::Plugin::ConfigLoader'   => '0.34';
requires 'Catalyst::Plugin::Static::Simple' => '0.33';
requires 'Catalyst::Action::RenderView'     => '0.16';
requires 'Catalyst::View::TT'               => '0.41';
requires 'Catalyst::Controller::REST'       => '1.17';
requires 'Catalyst::Model::DBIC::Schema'    => '0.65';
requires 'Catalyst::Plugin::Authentication' => '0.10023';
requires 'DBD::SQLite'                      => '1.40';
requires 'DBD::Pg'                          => '3.4.2';
requires 'DBIx::Class'                      => '0.08270';
requires 'FCGI'                             => '0';
requires 'JSON::Tiny'                       => '0';
requires 'Test::Pod::Coverage'              => '1.04';
requires 'Moose'                            => '2.1202';
requires 'MooseX::NonMoose'                 => '0.25';
requires 'namespace::autoclean'             => '0.22';
requires 'Config::General'                  => '2.56';
# This should reflect the config file format you've chosen
# See Catalyst::Plugin::ConfigLoader for supported formats

test_requires 'Test::More' => '0.88';
catalyst;

install_script glob('script/*.pl');
auto_install;
WriteAll;
