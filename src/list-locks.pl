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

list-locks.pl - View locks in Branch Locker.

=cut

use strict;
use warnings;

use Getopt::Long;
use FindBin qw($Bin);
use Pod::Usage;

use LWP::UserAgent;
use JSON::Tiny 'decode_json';

my $EMPTY_STR        = q{};
my $api_key_filename = 'branchlocker.api.key';

my $host             = 'localhost';
my $port             = 80;
my $debug            = 0;

sub debug_log ($$)
{
    my $message     = shift;
    my $print_level = shift;

    print "$message\n" if ($debug >= $print_level);
}

my $option_h   = 0;
my $option_man = 0;

=head1 SYNOPSIS

list-locks.pl [options]

  Options:
    -h|help           display this help message.
    -man              display a man page.

    -l|lock-id        display the lock that has the specified id.
    -b|branch         display locks that affect the named branch.
    -r|repository     display locks that affect the named repository.
    -g|gate-keeper    display locks that the named gate keeper can edit.

    -x                specify the debug level.

=head1 OPTIONS

=over

=item B<-h|help>

Display a brief help message and exit.

=item B<-man>

Display a verbose man page.

=item B<-l|lock-id>

Display the lock that has the specified id.

=item B<-b|branch>

Display locks that affect named branch.

=item B<-r|repository>

Display locks that affect named repository.

=item B<-g|gate-keeper>

Display locks that the named gate keeper can edit.

=back

=cut

sub get_api_result($$$$)
{
    my $api_key      = shift;
    my $criteria_ref = shift;
    my $api_call     = shift;
    my $handled_keys = shift;

    my $url  = "http://$host:$port/api/$api_call";

    my @key_value_pairs = ();

    foreach my $key (@$handled_keys) {
        my $value = $criteria_ref->{$key};
        push(@key_value_pairs, "$key=$value") if (defined $value);
    }

    $url .= '?' . join('&', @key_value_pairs) if (scalar @key_value_pairs);

    my $ua  = new LWP::UserAgent;
    my $req = new HTTP::Request(GET => $url);
    $req->header(
        'Content-Type' => 'application/json',
        'X-API-Key'    => $api_key,
    );

    my $res = $ua->request($req);
    my $result_ref = undef;

    # Check the outcome of the response
    if ($res->is_success && $res->content ne $EMPTY_STR ) {
        $result_ref = decode_json($res->content);
    }

    else {
        print STDERR "Response Code:    " . $res->code . "\n";
        print STDERR "Response Message: " . $res->message . "\n";
        print STDERR "Response Error:   " . $res->content . "\n";
    }

    return $result_ref;
}

sub get_locks($$)
{
    my $api_key      = shift;
    my $criteria_ref = shift;
    my @handled_keys = qw(lock_id branch repository gate_keeper);

    return get_api_result($api_key, $criteria_ref, 'legacy_lock', \@handled_keys);
}

sub get_locations_from_locks($$)
{
    my $api_key   = shift;
    my $locks_ref = shift;

    my @handled_keys = qw(id);
    my @lock_ids = ();

    foreach my $lock_ref (@$locks_ref) {
        push(@lock_ids, $lock_ref->{'id'});
    }

    return get_api_result(
        $api_key,
        { 'id' => join(',', @lock_ids) },
        'location',
        \@handled_keys
    );
}

sub get_api_key_from_file($)
{
    my $filename = shift;
    my $api_key = $EMPTY_STR;

    open (API_KEY, "<$filename")
        or die "Could not open file $filename: $!\n";
    $api_key = do { local $/; <API_KEY> };
    chomp ($api_key);
    close(API_KEY);

    return $api_key;
}

my $lock_id     = undef;
my $branch      = undef;
my $repository  = undef;
my $gate_keeper = undef;

GetOptions(
    "h|help"          => \$option_h,
    "man"             => \$option_man,

    "host=s"          => \$host,
    "port=s"          => \$port,

    "l|lock-id=s"     => \$lock_id,
    "b|branch=s"      => \$branch,
    "r|repository=s"  => \$repository,
    "g|gate-keeper=s" => \$gate_keeper,
    "k|key-file=s"    => \$api_key_filename,

    "x|debug=s"       => \$debug,
) or pod2usage();

pod2usage() if ($option_h);
pod2usage( -verbose => 2 ) if ($option_man);

my $criteria_ref = {};

$criteria_ref->{'lock_id'    } = $lock_id     if (defined $lock_id);
$criteria_ref->{'branch'     } = $branch      if (defined $branch);
$criteria_ref->{'repository' } = $repository  if (defined $repository);
$criteria_ref->{'gate_keeper'} = $gate_keeper if (defined $gate_keeper);

my @files = (
    $api_key_filename,
    $Bin         . "/$api_key_filename",
    $ENV{'HOME'} . "/$api_key_filename",
);

my $api_key = $EMPTY_STR;
foreach my $file (@files) {
    $api_key = get_api_key_from_file($file)
        if (-f $file);
}

my $locks_ref = get_locks($api_key, $criteria_ref);
exit 1 if (! defined $locks_ref);

my $locations_ref = get_locations_from_locks($api_key, $locks_ref);

# Setup location_refs for easy reference
my $locations_by_lock_id_ref = {};
foreach my $location_ref (@$locations_ref) {
    my $array_ref = $locations_by_lock_id_ref->{ $location_ref->{'lock_id'} }
        || [];

    push(@$array_ref, $location_ref);
    $locations_by_lock_id_ref->{ $location_ref->{'lock_id'} } = $array_ref;
}

# Print lock information
foreach my $lock_ref (@$locks_ref) {
    my $lock_id       = $lock_ref->{'id'           } || $EMPTY_STR;
    my $lock_name     = $lock_ref->{'name'         } || $EMPTY_STR;
    my $lock_state    = $lock_ref->{'state'        } || $EMPTY_STR;
    my $lock_status   = $lock_ref->{'status'       } || $EMPTY_STR;
    my $gate_keepers  = $lock_ref->{'gate_keepers' } || $EMPTY_STR;
    my $allowed_users = $lock_ref->{'allowed_users'} || $EMPTY_STR;
    my $allowed_prs   = $lock_ref->{'allowed_prs'  } || $EMPTY_STR;

    my $location_list = $locations_by_lock_id_ref->{$lock_id};
    my $locations_string = $EMPTY_STR;
    foreach my $location_ref (@$location_list) {
        my $loc_repository = $location_ref->{'repository'};
        my $loc_path       = $location_ref->{'path'      };  
        $locations_string .= ' ' x (13 - length $loc_repository)
            . "$loc_repository : $loc_path\n";
    }

    print <<OUTPUT;
      Lock ID : $lock_id
         Name : $lock_name
        State : $lock_state
       Status : $lock_status
 Gate Keepers : $gate_keepers
Allowed Users : $allowed_users
  Allowed PRs : $allowed_prs
    Locations :
$locations_string

OUTPUT
}

exit 0;

1;
