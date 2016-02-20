#!/usr/bin/perl

=head1 COPYRIGHT

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

=head1 AUTHOR

Justin Bellomi - justinb@juniper.net

=head1 NAME

unmake-admin.pl - Quick script to make a user not an admin.

=cut

use strict;
use warnings;

# Other Libraries
use DBWrap;

my $databases = ['branchlocker'];
my $database_name = 'branchlocker';
my $schema_name   = 'blr';

my $username = $ARGV[0];

die "unmake-admin.pl <username>\n" if (! defined $username);
die "Invalid username: $username" if ($username !~ /^[a-z]+$/);

$DBServers::readwrite_user   = 'blr_w';
$DBServers::readwrite_pass   = '';
$DBServers::readwrite_host   = 'localhost';

$DBServers::readonly_user    = 'blr_w';
$DBServers::readonly_pass    = '';
$DBServers::database_servers = { 'only' => ['localhost'] };

DBWrap::init({
    'writable' => 1,
    'databases' => $databases,
});

my $user = DBWrap::get_row_from_columns({
    'database' => $database_name,
    'schema'   => $schema_name,
    'table'    => 'bl_user',
    'columns'  => {
        'name' => $username,
    },
});

die "Could not find user: $username\n" if (! defined $user);

my $link = DBWrap::delete_rows_from_columns({
    'database' => $database_name,
    'schema'   => $schema_name,
    'table'    => 'bl_link_user_to_group',
    'columns'  => {
        'user_id'  => $user->{'id'},
        'group_id' => 1,
    },
});

die "Failed to unmake user an admin.\n" if (! defined $link);

print "User: $username is no longer an admin.\n";

exit 0;
