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

edit-locks.pl - Edit locks in Branch Locker.

=cut

use strict;
use warnings;

use IO::Select;
use FindBin qw($Bin);
use Getopt::Long;
use Pod::Usage;

use LWP::UserAgent;
use JSON::Tiny qw(encode_json decode_json);

my $EMPTY_STR        = q{};
my $api_key_filename = 'branchlocker.api.key';

my $host             = 'localhost';
my $port             = 80;
my $debug            = 0;
my $timeout          = 7200;

sub debug_log ($$)
{
    my $message     = shift;
    my $print_level = shift;

    print "$message\n" if ($debug >= $print_level);
}

sub put_api_result($$$)
{
    my $api_key     = shift;
    my $content_ref = shift;
    my $api_call    = shift;

    my $url  = "http://$host:$port/api/$api_call";

    my $json = encode_json($content_ref);

    my $ua  = new LWP::UserAgent;
    $ua->timeout($timeout);

    my $req = new HTTP::Request(PUT => $url);
    $req->header(
        'Content-Type' => 'application/json',
        'X-API-Key'    => $api_key,
    );
    $req->content($json);

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

sub put_lock($$$)
{
    my $api_key               = shift;
    my $criteria_ref          = shift;
    my $data_manipulation_ref = shift;

    my $data_ref = {
        'criteria'          => $criteria_ref,
        'data_manipulation' => $data_manipulation_ref,
    };

    return put_api_result($api_key, $data_ref, 'legacy_lock');
}

sub put_echo($$$)
{
    my $api_key               = shift;
    my $criteria_ref          = shift;
    my $data_manipulation_ref = shift;

    my $data_ref = {
        'criteria'          => $criteria_ref,
        'data_manipulation' => $data_manipulation_ref,
    };

    return put_api_result($api_key, $data_ref, 'echo');
}

sub get_api_key_from_file($)
{
    my $filename = shift;
    my $api_key = $EMPTY_STR;

    open (API_KEY, "<$filename")
        or die "Could not open file $filename: $!\n";
    $api_key = do { local $/; <API_KEY> };
    chomp ($api_key);

    return $api_key;
}

=head1 SYNOPSIS

edit-locks <-u username> <Lock Criteria> <Data Manipulation> [options]

  Required:
    -u|username              specify a user for branch locker database edits.

  Lock Criteria (At least one is required):
    -l|lock-id               edit the lock that has the specified id.
    -b|branch                edit locks that affect the named branch.
    -r|repository            edit locks that affect the named repository.
    -g|gate-keeper           edit locks that the named gate keeper can edit.

  Data Manipulation (At least one is required):
    -replace-message         replace the lock message with specified message.
    -set-status              set the lock status to open/restricted/closed.
    -set-state               set the lock state to active/eol.

    Legacy Support:
      -add-users             add users listed to the found locks.
      -remove-users          remove users listed from the found locks.

      -add-prs               add prs listed to the found locks.
      -remove-prs            remove prs listed from the found locks.

      -add-gate-keepers      add gate keepers listed to the found locks.
      -remove-gate-keepers   remove gate keepers listed from the found locks.

  Options:
    -h|help                  display this help message.
    -man                     display a man page.

    -d|database              specify a non standard branch locker database.

    -x                       specify the debug level.

=head1 OPTIONS

=over

=item B<-h|help>

Display a brief help message and exit.

=item B<-man>

Display a verbose man page.

=item B<-d|database>

Edit locks in the specified database.

=item B<-x|debug>

Specify a debug level when running the script.

=head2 Required

=item B<-u|username>

Edit locks as the specified user.

=head2 Lock Criteria

One Lock Criterion option is required.

=item B<-l|lock-id>

Edit the lock that has the specified id.

=item B<-b|branch>

Edit locks that affect named branch.

=item B<-r|repository>

Edit locks that affect named repository.

=item B<-g|gate-keeper>

Edit locks that the named gate keeper can edit.

=head2 Data Manipulation (At least one is required):

One Data Manipulation option is required.

=item B<-replace-message>

Replace the lock message with specified message.

=item B<-set-state>

Set the lock state to active/eol.

=head3 Legacy Support:

=item B<-set-status>

Set the lock status to open/restricted/closed.

=item B<-add-users>

Add users listed to the found locks.

=item B<-remove-users>

Remove users listed from the found locks.

=item B<-add-prs>

Add prs listed to the found locks.

=item B<-remove-prs>

Remove prs listed from the found locks.

=item B<-add-gate-keepers>

Add gate keepers listed to the found locks.

=item B<-remove-gate-keepers>

Remove gate keepers listed from the found locks.

=back

=cut

my $option_h   = 0;
my $option_man = 0;

my $create_lock         = undef;

my $lock_id             = undef;
my $username            = getpwuid($<);
my $database            = undef;
my $branch              = undef;
my $repository          = undef;
my $gate_keeper         = undef;

my $add_users           = undef;
my $remove_users        = undef;

my $add_prs             = undef;
my $remove_prs          = undef;

my $add_gate_keepers    = undef;
my $remove_gate_keepers = undef;

my $replace_message     = undef;

my $set_status          = undef;

my $set_state           = undef;

GetOptions(
    "h|help"                 => \$option_h,
    "man"                    => \$option_man,

    "host=s"                 => \$host,
    "port=s"                 => \$port,

    "u|username=s"           => \$username,
    "d|database=s"           => \$database,
    "x|debug=s"              => \$debug,

    "l|lock-id=s"            => \$lock_id,
    "b|branch=s"             => \$branch,
    "r|repository=s"         => \$repository,
    "g|gate-keeper=s"        => \$gate_keeper,
    "k|key-file=s"           => \$api_key_filename,

    "c|create-lock"          => \$create_lock,

    "add-users=s"            => \$add_users,
    "remove-users=s"         => \$remove_users,

    "add-prs=s"              => \$add_prs,
    "remove-prs=s"           => \$remove_prs,

    "add-gate-keepers=s"     => \$add_gate_keepers,
    "remove-gate-keepers=s"  => \$remove_gate_keepers,

    "replace-message=s"      => \$replace_message,

    "set-status=s"           => \$set_status,

    "set-state=s"            => \$set_state,
) or pod2usage();

pod2usage() if ($option_h);
pod2usage( -verbose => 2 ) if ($option_man);
pod2usage() if (! defined $username || $username eq $EMPTY_STR);

my $criteria_ref = {};

$criteria_ref->{'lock_id'    } = $lock_id     if (defined $lock_id);
$criteria_ref->{'branch'     } = $branch      if (defined $branch);
$criteria_ref->{'repository' } = $repository  if (defined $repository);
$criteria_ref->{'gate_keeper'} = $gate_keeper if (defined $gate_keeper);

pod2usage() if (scalar keys %$criteria_ref == 0);

my $s = IO::Select->new();
$s->add(\*STDIN);

if ($s->can_read(.5)) {
    my $stdin = do { local $/; <> };
    if ($stdin ne $EMPTY_STR) {
        $replace_message = $stdin;
    }
}

my $data_manipulation_ref = {};

$data_manipulation_ref->{'add-users'}
    = $add_users if (defined $add_users);

$data_manipulation_ref->{'remove-users'}
    = $remove_users if (defined $remove_users);

$data_manipulation_ref->{'add-prs'}
    = $add_prs if (defined $add_prs);

$data_manipulation_ref->{'remove-prs'}
    = $remove_prs if (defined $remove_prs);

$data_manipulation_ref->{'add-gate-keepers'}
    = $add_gate_keepers if (defined $add_gate_keepers);

$data_manipulation_ref->{'remove-gate-keepers'}
    = $remove_gate_keepers if (defined $remove_gate_keepers);

$data_manipulation_ref->{'replace-message'}
    = $replace_message if (defined $replace_message);

$data_manipulation_ref->{'set-status'}
    = $set_status if (defined $set_status);

$data_manipulation_ref->{'set-state'}
    = $set_state if (defined $set_state);

pod2usage() if (scalar keys %$data_manipulation_ref == 0);

$data_manipulation_ref->{'auto-create-lock'}
    = 1 if (defined $create_lock);

$data_manipulation_ref->{'as-user'} = $username;

my $result = undef;

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

if ($debug) {
    $result = put_echo($api_key, $criteria_ref, $data_manipulation_ref);
    use Data::Dumper;
    print Dumper($result);
}

else {
    $result = put_lock($api_key, $criteria_ref, $data_manipulation_ref);
}

exit 1 if (! defined $result);

exit 0;

1;

