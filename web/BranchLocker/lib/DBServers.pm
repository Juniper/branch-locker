
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

DBServers.pm - Collection of common variables for use with the database
servers.

=head1 SYNOPSIS

use DBServers;

=head1 Subroutines

=over

=cut

use strict;
use warnings;

package DBServers;

my $EMPTY_STR = q{};

our $database_servers = {
    'local' => ['localhost'],
    'another' => [],
    'a third' => [],
};

sub shuffle {
    my @a = splice @_;
    foreach my $i (0 .. $#a) {
        my $j = int rand @a;
        @a[$i, $j] = @a[$j, $i];
    }
    return @a;
}

sub get_server_order {
    my $ping_times = {};
    foreach my $location (keys %$database_servers) {
        my $servers_ref = $database_servers->{$location};
        my @servers = @$servers_ref;
        my $index = 0;

        foreach my $server (@servers) {
            my $remove_server = 0;
            open(PING, "ping -c 1 $server 2>&1 |")
                || open(PING, "/sbin/ping -c 1 $server 2>&1 |");
            while(<PING>) {
                my $line = $_;
                if ($line =~ /time=([0-9]+\.[0-9]+)/) {
                    my $time = $1;
                    $ping_times->{$location} = $time
                        if (! exists $ping_times->{$location}
                            || $ping_times->{$location} > $time);
                }
                elsif ($line =~ /time=([0-9]+)/) {
                    my $time = $1;
                    $ping_times->{$location} = $time
                        if (! exists $ping_times->{$location}
                            || $ping_times->{$location} > $time);
                }
                elsif ($line =~ /100\.0% packet loss/) {
                    $remove_server = 1;
                }
            }

            if ($remove_server) {
                splice (@$servers_ref, $index, 1);
            }
            else {
                $index++;
            }
        }
    }

    my @server_order = ();
    foreach my $location (
        sort{ $ping_times->{$a} <=> $ping_times->{$b} } keys %$ping_times) {
        push(@server_order, shuffle(@{ $database_servers->{$location} }));
    }

    return @server_order;
}

our $readwrite_host = 'localhost';
our $readwrite_user = getpwuid($<);
our $readwrite_pass = $EMPTY_STR;

our $readonly_user  = 'readonly';
our $readonly_pass  = $EMPTY_STR;

1;
