
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

Branch::Locker - Wrapper around the DBWrap.pm for Branch Locker specific
functions.

=cut

use strict;
use warnings;

use Data::Dumper;

# Other Libraries
use DBWrap;

package Branch::Locker;

our $database_name    = 'branchlocker';
our $schema_name      = 'blr';

our $readwrite_user   = undef;
our $readwrite_pass   = undef;
our $readwrite_host   = 'localhost';

our $readonly_user    = undef;
our $readonly_pass    = undef;
our $database_servers = { 'local' => ['localhost'] };

our $debug_level      = 0;
our $debug_log        = \&print_debug;
our $errors_key       = 'errors';

my $EMPTY_STR   = q{};
my $UNKNOWN_KEY = '__UNKNOWN_KEY__';

my $LEGACY_ENFORCEMENT_NAME = 'Legacy Enforcement';

=head1 SYNOPSIS

use Branch::Locker;
Branch::Locker::init($hash_ref);

=head1 Subroutines

=over

=item print_debug

Handles printing debug messages.  Accepts a message and a debug level.

=cut

sub print_debug
{
    my $message       = shift;
    my $verbose_level = shift || 1;

    if (defined $message
        && $debug_level >= $verbose_level
    ) {
        print <<DEBUG;
DEBUG $verbose_level:
$message
DEBUG
    }
}

=item init($)

Initializing connections to databases, expects a hash reference that
has a key specifying databases to use.  And an optional key to connect to
writable databases.

=cut

sub init($)
{
    my $hash_ref = shift;

    $DBServers::readwrite_user   = $readwrite_user;
    $DBServers::readwrite_pass   = $readwrite_pass;
    $DBServers::readwrite_host   = $readwrite_host;

    $DBServers::readonly_user    = $readonly_user;
    $DBServers::readonly_pass    = $readonly_pass;
    $DBServers::database_servers = $database_servers;

    DBWrap::init($hash_ref);

    my $api_key = $hash_ref->{'api_key'} || $EMPTY_STR;
    my $api_key_ref = DBWrap::get_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_api_key',
        'columns'  => {
            'api_key' => $api_key,
        },
    });

    return $api_key_ref;
}

sub get_added_and_removed_values($$)
{
    my $old_values = shift;
    my $new_values = shift;

    # Some short circuit logic.
    return ([], []) if ($old_values eq $new_values);

    my $old_array_ref = get_array_ref_from_ref($old_values);
    my $new_array_ref = get_array_ref_from_ref($new_values);

    my %old_hash = map { $_ => 1 } @$old_array_ref;
    my %new_hash = map { $_ => 1 } @$new_array_ref;

    # If a value exists in the new list, but was not present in the old list
    # it has been added.
    my $added_values = [];
    foreach my $value (keys %new_hash) {
        push(@$added_values, $value) if (! exists $old_hash{$value});
    }

    # If a value existed in the old list, but is not present in the new list
    # it has been removed.
    my $removed_values = [];
    foreach my $value (keys %old_hash) {
        push(@$removed_values, $value) if (! exists $new_hash{$value});
    }

    return ($added_values, $removed_values);
}

=item get_array_ref_from_ref($@)

Helper function to parse any of the following arguments, returning a
reference to an array that holds scalars.  If one of the references is a hash
reference a second argument is required specifying which key to use.

=over

an array reference holding hash references whos hash_key holds a scalar,

an array reference holding scalars,

an array reference holding a combination of scalars and hash references whos
hash_key holds a scalar.

a single hash reference whos hash_key holds a scalar,

a comma separated list of scalar,

a single scalar,

=back

=cut

sub get_array_ref_from_ref($@)
{
    my $check_ref = shift;
    my $hash_key  = shift;

    my $ENO_HASH_KEY = <<ENO_HASH_KEY;
Cannot get_array_ref_from_ref using HASH and no hash_key.
ENO_HASH_KEY

    my $array_ref = [];
    if (ref $check_ref eq $EMPTY_STR) {
        # Handle undef $check_ref
        if (defined $check_ref) {
            # We have a single element.
            # Handle a comma separated list.
            my $unique_ref = {};
            foreach my $cur_element (split(/[, \r\n]+/, $check_ref)) {
                $unique_ref->{$cur_element} = 1;
            }

            push(@$array_ref, keys %$unique_ref);
        }
    }

    elsif (ref $check_ref eq 'ARRAY') {
        # We have a list of references.
        foreach my $element_ref (@$check_ref) {
            if (ref $element_ref eq $EMPTY_STR) {
                # We have a single element.
                push(@$array_ref, $element_ref);
            }
            elsif (ref $element_ref eq 'HASH') {
                # We have a lock reference
                if (defined $hash_key) {
                    push(@$array_ref, $element_ref->{$hash_key});
                }
                else {
                    die $ENO_HASH_KEY;
                }
            }
        }
    }

    elsif (ref $check_ref eq 'HASH') {
        # We have a single lock reference
        if (defined $hash_key) {
            push(@$array_ref, $check_ref->{$hash_key});
        }
        else {
            die $ENO_HASH_KEY;
        }
    }

    return $array_ref;
}

sub add_errors($$@)
{
    my $audit_transaction_ref = shift;
    my $http_error_code       = shift;
    my @errors                = @_;

    my $errors_ref = $audit_transaction_ref->{$errors_key};
    if (! defined $errors_ref) {
        $errors_ref = [];
        $audit_transaction_ref->{$errors_key} = $errors_ref;
    }

    push(@$errors_ref, @errors);
    $audit_transaction_ref->{'http_error_code'} = $http_error_code;
}

sub get_column_info_from_table($)
{
    my $table_name = shift;
    my $columns = DBWrap::get_rows_from_columns({
        'database' => $database_name,
        'schema'   => 'information_schema',
        'table'    => 'columns',
        'columns'  => {
            'table_schema' => $schema_name,
            'table_name'   => $table_name,
        },
    });

    return $columns;
}

sub get_column_names_from_table($)
{
    my $table_name = shift;
    my $column_info_ref = get_column_info_from_table($table_name);
    my $column_names = [];
    foreach my $column_ref (@$column_info_ref) {
        push(@$column_names, $column_ref->{'column_name'});
    }

    return $column_names;
}

sub start_audit_transaction($$$)
{
    my $api_key_ref      = shift;
    my $data_dump_string = shift;
    my $as_user          = shift;

    my $user_ref = DBWrap::find_or_create_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_user',
        'columns'  => {
            'name' => $as_user,
        },
    });

    my $audit_transaction_ref = DBWrap::insert_row({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_audit_transaction',
        'columns'  => {
            'api_key_id' => $api_key_ref->{'id'},
            'as_user_id' => $user_ref->{'id'},
            'data_dump'  => $data_dump_string,
        },
    });

    if (! defined $audit_transaction_ref) {
        $audit_transaction_ref = {};
        add_errors(
            $audit_transaction_ref,
            500,
            'Error creating audit_transaction.',
        );

        return $audit_transaction_ref;
    }

    if ($api_key_ref->{'user_id'} != $user_ref->{'id'}
        && ! $api_key_ref->{'can_impersonate'}) {
        my $user_ref = DBWrap::find_or_create_row_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'bl_user',
            'columns'  => {
                'id' => $api_key_ref->{'user_id'},
            },
        });

        my $username = $user_ref->{'name'};

        add_errors(
            $audit_transaction_ref,
            403,
            "You are only authorized to edit as '$username'."
        );

        return end_audit_transaction($audit_transaction_ref);
    }

    return $audit_transaction_ref;
}

sub end_audit_transaction($)
{
    my $audit_transaction_ref = shift;

    my $result_ref = DBWrap::update_or_insert_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_audit_transaction',
        'ids_ref'  => { 'id' => $audit_transaction_ref->{'id'} },
        'columns'  => { 'end_timestamp' => 'now()', },
    });

    if (! defined $result_ref) {
        add_errors(
            $audit_transaction_ref,
            500,
            'Error ending audit_transaction.',
        );
    }
    else {
        $audit_transaction_ref->{'end_timestamp'}
            = $result_ref->{'end_timestamp'};
    }

    return $audit_transaction_ref;
}

=item get_locks($)

Fetch locks from the database according to the passed criteria, which is a
hash_ref.

=cut

my $get_locks_criteria_dispatch_ref = {
    'lock_id'     => \&get_locks_handle_lock_id_key,
    'branch'      => \&get_locks_handle_location_keys,
    'repository'  => \&get_locks_handle_location_keys,
    'gate_keeper' => \&get_locks_handle_gate_keeper_key,
    'state'       => \&get_locks_handle_state_key,
    'grouped'     => \&get_locks_handle_grouped_key,
    $UNKNOWN_KEY  => \&get_locks_handle_unknown_key,
};

sub get_locks($)
{
    my $criteria_ref = shift;

    my @clauses = ();
    foreach my $key (keys %$criteria_ref) {
        my $subroutine_ref = $get_locks_criteria_dispatch_ref->{$key}
            || $get_locks_criteria_dispatch_ref->{$UNKNOWN_KEY};
        my $clause = &$subroutine_ref($criteria_ref);
        if (defined $clause) {
            push(@clauses, $clause) if (defined $clause);
            return [] if ($clause eq $EMPTY_STR);
        }
    }

    my $sql = <<SQL;
SELECT *
FROM   $schema_name.view_locks
SQL

    if (scalar @clauses) {
        $sql .= 'WHERE ' . join(' AND ', @clauses);
    }

    return DBWrap::sql_returning_rows({
        'database' => $database_name,
        'sql'      => $sql,
    });
}

=item get_locks_handle_unknown_key($)

If there is a key that is not handled return undef, nothing will be done.

=cut

sub get_locks_handle_unknown_key($)
{
    return undef;
}

=item get_locks_handle_lock_id_key($)

Triggered by lock_id key.

=cut

sub get_locks_handle_lock_id_key($)
{
    my $criteria_ref = shift;
    my $subroutine   = (caller(0))[3];

    my $cache = $criteria_ref->{'cache'}->{$subroutine};
    return undef if (defined $cache);

    my $ids_ref = get_array_ref_from_ref($criteria_ref->{'lock_id'}, 'id');
    my $ids_string = join(',', @$ids_ref);

    my $resulting_sql
        = $ids_string ne $EMPTY_STR ? "$schema_name.view_locks.id in ($ids_string)"
        :                             $EMPTY_STR
        ;

    $criteria_ref->{'cache'}->{$subroutine} = $resulting_sql;
    return $resulting_sql;
}

=item get_locks_handle_location_keys($)

Can be triggered by a 'branch' and/or 'repository' criteria key.

=cut

sub get_locks_handle_location_keys($)
{
    my $criteria_ref = shift;
    my $subroutine   = (caller(0))[3];

    my $cache = $criteria_ref->{'cache'}->{$subroutine};
    return undef if (defined $cache);

    my $branch     = $criteria_ref->{'branch'    };
    my $repository = $criteria_ref->{'repository'};

    my $path = undef;
    my $sql = undef;

    if (defined $branch) {
        if ($branch eq '/trunk/' || $branch =~ m:/branches/[^/]+:) {
            $path = $branch;
        }
        elsif ($branch =~ m:^(main\.trunk|/trunk|trunk)$:) {
            $path = '/trunk/';
        }
        else {
            $branch =~ s:^/::;
            $path = "/branches/$branch";
        }
    
        if ($path !~ m:/$:){
            $path .= '/';
        }

        $path = DBWrap::sql_quote($path);
        $sql = <<SQL;
SELECT DISTINCT $schema_name.view_lock_locations.lock_id
FROM   $schema_name.view_lock_locations
WHERE ($path like $schema_name.view_lock_locations.path || '%')
SQL
    }

    if (defined $repository) {
        $repository = DBWrap::sql_quote($repository);
        if (defined $sql) {
            $sql .= 'AND ';
        }
        else {
            $sql = <<SQL;
SELECT DISTINCT $schema_name.view_lock_locations.lock_id
FROM   $schema_name.view_lock_locations
WHERE
SQL
        }
        $sql .= "$schema_name.view_lock_locations.repository = $repository";
    }

    my $ids = DBWrap::sql_returning_rows({
        'database' => $database_name,
        'sql'      => $sql,
    });

    return undef if (! defined $ids);
    return $EMPTY_STR if (! scalar @$ids);

    my @result = ();
    map { push(@result, $_->{'lock_id'}) } @$ids;

    my $resulting_sql = "$schema_name.view_locks.id IN (" . join(',', @result) . ')';
    $criteria_ref->{'cache'}->{$subroutine} = $resulting_sql;
    return $resulting_sql;
}

=item get_locks_handle_gate_keeper_key($)

Look up locks according to gate keeper.

=cut

sub get_locks_handle_gate_keeper_key($)
{
    my $criteria_ref = shift;
    my $subroutine   = (caller(0))[3];

    my $cache = $criteria_ref->{'cache'}->{$subroutine};
    return undef if (defined $cache);

    my $gate_keeper
        = DBWrap::sql_quote($criteria_ref->{'gate_keeper'} || $EMPTY_STR);

    my $sql = <<SQL;
SELECT DISTINCT $schema_name.view_lock_gate_keepers.lock_id
FROM   $schema_name.view_lock_gate_keepers
WHERE  $schema_name.view_lock_gate_keepers.gate_keeper = $gate_keeper
SQL

    my $ids = DBWrap::sql_returning_rows({
        'database' => $database_name,
        'sql'      => $sql,
    });

    return undef if (! defined $ids);
    return $EMPTY_STR if (! scalar @$ids);

    my @result = ();
    map { push(@result, $_->{'lock_id'}) } @$ids;

    my $resulting_sql = "$schema_name.view_locks.id IN (" . join(',', @result) . ')';
    $criteria_ref->{'cache'}->{$subroutine} = $resulting_sql;
    return $resulting_sql;
}

=item get_locks_handle_state_key($)

Look up locks according to State.

=cut

sub get_locks_handle_state_key($)
{
    my $criteria_ref = shift;
    my $subroutine   = (caller(0))[3];

    my $cache = $criteria_ref->{'cache'}->{$subroutine};
    return undef if (defined $cache);

    my $state = $criteria_ref->{'state'};
    return undef if (! defined $state);

    my $resulting_sql = "$schema_name.view_locks.state = '$state'";
    $criteria_ref->{'cache'}->{$subroutine} = $resulting_sql;
    return $resulting_sql;
}

=item get_locks_handle_grouped_key($)

Look up locks according to Grouped value.

=cut

sub get_locks_handle_grouped_key($)
{
    my $criteria_ref = shift;
    my $subroutine   = (caller(0))[3];

    my $cache = $criteria_ref->{'cache'}->{$subroutine};
    return undef if (defined $cache);

    my $grouped = $criteria_ref->{'grouped'};
    return undef if (! defined $grouped);

    my $group_values = get_array_ref_from_ref($grouped);
    my @quoted_group_values = map { DBWrap::sql_quote($_) } @$group_values;
    my $grouped_string = join(',', @quoted_group_values);

    my $resulting_sql = "$schema_name.view_locks.grouped in ($grouped_string)";
    $criteria_ref->{'cache'}->{$subroutine} = $resulting_sql;
    return $resulting_sql;
}

sub get_locks_using_enforcements($)
{
    my $enforcements_ref = shift;
    my $ids_ref = get_array_ref_from_ref($enforcements_ref, 'id');

    my $links_ref = DBWrap::get_rows_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_link_enforcement_to_lock',
        'columns'  => { 'enforcement_id' => $ids_ref, },
    });

    my $lock_ids  = get_array_ref_from_ref($links_ref, 'lock_id');
    return get_locks({ 'lock_id' => $lock_ids });
}

=item get_locations_from_locks($)

Get location references from one of:

=over

an array reference holding lock_references,

an array reference holding lock ids,

a single lock reference,

a single lock id,

=back

=cut

sub get_locations_from_locks($)
{
    my $check_ref = shift;

    my $ids_ref = get_array_ref_from_ref($check_ref, 'id');
    if (scalar @$ids_ref) {
        return DBWrap::get_rows_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'view_lock_locations',
            'columns'  => { 'lock_id' => $ids_ref, },
        });
    }
    else {
        return [];
    }
}

sub set_enforcement_is_enabled($$)
{
    my $enforcement_ref = shift;
    my $value           = shift;

    # Check if user has permissions.

    DBWrap::update_row({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_enforcement',
        'ids_ref'  => { 'id' => $enforcement_ref->{'id'}, },
        'columns'  => { 'is_enabled' => $value, },
    });
}

sub enable_enforcement($)
{
    my $enforcement_ref = shift;
    return set_enforcement_is_enabled($enforcement_ref, 'true');
}

sub disable_enforcement($)
{
    my $enforcement_ref = shift;
    return set_enforcement_is_enabled($enforcement_ref, 'false');
}

sub get_enforcements_from_lock($)
{
    my $lock_ref = shift;

    my $lock_id = $lock_ref->{'id'};

    if (defined $lock_id) {
        my $lock_enforcements = DBWrap::get_rows_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'view_lock_enforcements',
            'columns'  => { 'lock_id' => $lock_id, },
        });

        my $enforcement_ids
            = get_array_ref_from_ref($lock_enforcements, 'enforcement_id');

        if (scalar @$enforcement_ids) {
            return DBWrap::get_rows_from_columns({
                'database' => $database_name,
                'schema'   => $schema_name,
                'table'    => 'view_enforcements',
                'columns'  => { 'id' => $enforcement_ids, },
            });
        }
        else {
            return undef;
        }
    }
    else {
        return undef;
    }
}

my $edit_locks_data_manipulation_dispatch_ref = {
    'add-users'           => \&edit_locks_handle_add_users_key,
    'remove-users'        => \&edit_locks_handle_remove_users_key,
    'add-prs'             => \&edit_locks_handle_add_prs_key,
    'remove-prs'          => \&edit_locks_handle_remove_prs_key,
    'add-gate-keepers'    => \&edit_locks_handle_add_gate_keepers_key,
    'remove-gate-keepers' => \&edit_locks_handle_remove_gate_keepers_key,
    'replace-message'     => \&edit_locks_handle_replace_message_key,
    'set-status'          => \&edit_locks_handle_set_status_key,
    'set-state'           => \&edit_locks_handle_set_state_key,
    'as-user'             => \&edit_locks_ignore_key,
    $UNKNOWN_KEY          => \&edit_locks_ignore_key,
};

sub edit_locks_ignore_key($$)
{
    return [];
}

sub edit_locks($$$)
{
    my $api_key_ref           = shift;
    my $locks_ref             = shift;
    my $data_manipulation_ref = shift;

    return if (scalar @$locks_ref == 0);

    my $as_user = $data_manipulation_ref->{'as-user'};
    my $data_dump = Data::Dumper::Dumper({
        'locks'                 => $locks_ref,
        'data_manipulation_ref' => $data_manipulation_ref,
    });

    my $audit_transaction_ref = start_audit_transaction(
        $api_key_ref,
        $data_dump,
        $as_user,
    );

    return $audit_transaction_ref
        if (exists $audit_transaction_ref->{$errors_key});

    foreach my $key (keys %$data_manipulation_ref) {
        my $subroutine_ref
            = $edit_locks_data_manipulation_dispatch_ref->{$key}
            || $edit_locks_data_manipulation_dispatch_ref->{$UNKNOWN_KEY};

        my $resulting_errors = &$subroutine_ref(
            $locks_ref,
            $data_manipulation_ref
        );

        if (scalar @$resulting_errors) {
            add_errors(
                $audit_transaction_ref,
                400,
                @$resulting_errors,
            );
        }
    }

    return $audit_transaction_ref
        if (exists $audit_transaction_ref->{$errors_key});

    $audit_transaction_ref->{'result'}
        = get_locks({ 'lock_id' => $locks_ref });

    return end_audit_transaction($audit_transaction_ref);
}

sub link_location_to_lock($$)
{
    my $location_ref = shift;
    my $lock_ref     = shift;

    my $sub = (caller(0))[3];
    &$debug_log("start: $sub($location_ref, $lock_ref)", 5);

    my $location_id = $location_ref->{'id'}
        || die "$sub - location_ref must have key id.";

    my $lock_id = $lock_ref->{'id'}
        || die "$sub - lock_ref must have key id.";

    my $table_name = 'bl_link_location_to_lock';
    my $link_ref = DBWrap::find_or_create_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => $table_name,
        'columns'  => {
            'location_id' => $location_id,
            'lock_id'     => $lock_id,
        },
    });

    die "Error finding or creating $table_name.\n"
        if (! defined $link_ref);

    &$debug_log("  end: $sub($location_ref, $lock_ref)", 5);
}

sub link_enforcement_to_lock($$)
{
    my $enforcement_ref = shift;
    my $lock_ref        = shift;

    my $sub = (caller(0))[3];
    &$debug_log("start: $sub($enforcement_ref, $lock_ref)", 5);

    my $enforcement_id = $enforcement_ref->{'id'}
        || die "$sub - enforcement_ref must have key id.";

    my $lock_id = $lock_ref->{'id'}
        || die "$sub - lock_ref must have key id.";

    my $table_name = 'bl_link_enforcement_to_lock';
    my $link_ref = DBWrap::find_or_create_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => $table_name,
        'columns'  => {
            'enforcement_id' => $enforcement_id,
            'lock_id'        => $lock_id,
        },
    });

    die "Error finding or creating $table_name.\n"
        if (! defined $link_ref);

    &$debug_log("  end: $sub($enforcement_ref, $lock_ref)", 5);
}

sub find_or_create_location_from_path_and_repository($$)
{
    my $path       = shift;
    my $repository = shift;

    my $path_ref = DBWrap::find_or_create_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_path',
        'columns'  => { 'name' => $path },
    });
    die "Error finding or creating path $path\n"
        if (! defined $path_ref);

    my $repository_ref = DBWrap::find_or_create_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_repository',
        'columns'  => { 'name' => $repository },
    });
    die "Error finding or creating repository $repository\n"
        if (! defined $repository_ref);

    return DBWrap::find_or_create_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_location',
        'columns'  => {
            'path_id'       => $path_ref->{'id'},
            'repository_id' => $repository_ref->{'id'},
        },
    });
}

sub find_or_create_enforcement_from_lock_and_name($$)
{
    my $lock_ref         = shift;
    my $enforcement_name = shift;

    my $sub = (caller(0))[3];
    &$debug_log("start: $sub($lock_ref, $enforcement_name)", 5);

    my $enforcement_ref = undef;

    &$debug_log(<<DEBUG, 4);
    - finding view_lock_enforcements: DBWrap::get_row_from_columns
DEBUG
    &$debug_log(<<DEBUG, 5);
        database : $database_name,
        schema   : $schema_name,
        table    : 'view_lock_enforcements',
        columns  : {
            lock_id          : $lock_ref->{'id'},
            enforcement_name : $enforcement_name,
        },
DEBUG
    my $lock_enforcement_ref = DBWrap::get_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'view_lock_enforcements',
        'columns'  => {
            'lock_id'          => $lock_ref->{'id'},
            'enforcement_name' => $enforcement_name,
        },
    });

    if (defined $lock_enforcement_ref) {
        &$debug_log(<<DEBUG, 4);
    - link-lock-to-enforcement found
    - finding enforcement record - DBWrap::get_row_from_columns
DEBUG
        $enforcement_ref = DBWrap::get_row_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'bl_enforcement',
            'columns' => {
                'id' => $lock_enforcement_ref->{'enforcement_id'},
            },
        });
    }

    if (! defined $enforcement_ref) {
        &$debug_log(<<DEBUG, 4);
    - creating enforcement - DBWrap::insert_row
DEBUG
        $enforcement_ref = DBWrap::insert_row({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'bl_enforcement',
            'columns' => {
                'name'       => $enforcement_name,
                'is_enabled' => 1,
            },
        });
        link_enforcement_to_lock($enforcement_ref, $lock_ref);
    }

    &$debug_log("  end: $sub($lock_ref, $enforcement_name)", 5);
    return $enforcement_ref;
}

sub find_or_create_users_from_usernames($$)
{
    my $check_ref = shift;
    my $errors    = shift;

    my $usernames_ref = get_array_ref_from_ref($check_ref, 'name');

    my $users_ref = [];
    foreach my $username (@$usernames_ref) {
        next if (! defined $username || $username eq $EMPTY_STR);
        if ($username !~ /^[a-z-_]+$/) {
            push(@$errors, "Invalid username: '$username'");
            next;
        }

        my $user_ref = DBWrap::find_or_create_row_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'bl_user',
            'columns'  => { 'name' => $username },
        });

        if (! defined $user_ref) {
            push(@$errors, "Error finding or creating user '$username'");
            next;
        }

        push (@$users_ref, $user_ref);
    }

    return $users_ref;
}

sub add_users_to_enforcement($$)
{
    my $users_ref             = shift;
    my $enforcement_ref       = shift;

    my $enforcement_id = $enforcement_ref->{'id'};

    my $errors = [];
    my $table_name = 'bl_link_user_to_enforcement_is_allowed';
    foreach my $cur_user_ref (@$users_ref) {
        my $user_id = $cur_user_ref->{'id'};
        my $link_ref = DBWrap::find_or_create_row_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => $table_name,
            'columns'  => {
                'enforcement_id' => $enforcement_id,
                'user_id'        => $user_id,
            },
        });

        if (! defined $link_ref) {
            push(@$errors, <<ERROR);
Error finding or creating $table_name, user_id: '$user_id'
ERROR
        }
    }
    return $errors;
}

sub remove_users_from_enforcement($$)
{
    my $users_ref             = shift;
    my $enforcement_ref       = shift;

    my $enforcement_id = $enforcement_ref->{'id'};

    foreach my $cur_user_ref (@$users_ref) {
        my $user_id = $cur_user_ref->{'id'};
        my $table_name = 'bl_link_user_to_enforcement_is_allowed';
        my $link_ref = DBWrap::get_row_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => $table_name,
            'columns'  => {
                'enforcement_id' => $enforcement_id,
                'user_id'        => $user_id,
            },
        });

        if (defined $link_ref) {
            my $link_id = $link_ref->{'id'};
            DBWrap::delete_rows_from_columns({
                'database' => $database_name,
                'schema'   => $schema_name,
                'table'    => $table_name,
                'columns'  => { 'id' => $link_id },
            });
        }
    }
}

sub get_user_from_name($)
{
    my $name = shift;

    return DBWrap::get_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_user',
        'columns'  => { 'name' => $name },
    });
}

sub get_user_from_id($)
{
    my $id = shift;

    return DBWrap::get_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_user',
        'columns'  => { 'id' => $id },
    });
}

sub is_user_an_admin($)
{
    my $check_ref = shift;

    my $user = undef;
    if (ref $check_ref eq $EMPTY_STR) {
        # Handle undef $check_ref
        if (defined $check_ref) {
            # We have a single element.
            $user = get_user_from_name($check_ref);
        }
    }

    elsif (ref $check_ref eq 'HASH') {
        $user = $check_ref;
    }

    my $result = undef;
    if (defined $user) {
        $result = DBWrap::get_row_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'view_admins',
            'columns'  => { 'user_id' => $user->{'id'}, },
        });
    }

    return (defined $result);
}

sub can_enable_enforcement_as_user($$$)
{
    my $enforcement = shift;
    my $as_user     = shift;
    my $errors      = shift;

    my $enforcement_id = $enforcement->{'id'};
    my $user = DBWrap::get_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_user',
        'columns'  => { 'name' => $as_user, },
    });

    if (! defined $user) {
        push(@$errors, "Username '$as_user' is not defined in database.");
        return undef;
    }

    return 1 if (is_user_an_admin($user));

    my $link = DBWrap::get_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_link_user_to_enforcement_can_enable',
        'columns'  => {
            'user_id'        => $user->{'id'},
            'enforcement_id' => $enforcement_id,
        },
    });

    if (! defined $link) {
        push(@$errors, "Enforcement ID: $enforcement_id - User '$as_user' does not have enable permissions.");
        return undef;
    }

    return 1;
}

sub can_edit_enforcement_as_user($$$)
{
    my $enforcement = shift;
    my $as_user     = shift;
    my $errors      = shift;

    my $enforcement_id = $enforcement->{'id'};
    my $user = DBWrap::get_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_user',
        'columns'  => { 'name' => $as_user, },
    });

    if (! defined $user) {
        push(@$errors, "Username '$as_user' is not defined in database.");
        return undef;
    }

    return 1 if (is_user_an_admin($user));

    my $link = DBWrap::get_row_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_link_user_to_enforcement_can_edit',
        'columns'  => {
            'user_id'        => $user->{'id'},
            'enforcement_id' => $enforcement_id,
        },
    });

    if (! defined $link) {
        push(@$errors, "Enforcement ID: $enforcement_id - User '$as_user' does not have edit permissions.");
        return undef;
    }

    return 1;
}

sub edit_locks_handle_add_users_key($$$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $as_user               = $data_manipulation_ref->{'as-user'};

    return ['add-users: You must define the as-user key.']
        if (! defined $as_user);

    my $errors = [];
    my $users = find_or_create_users_from_usernames(
        $data_manipulation_ref->{'add-users'},
        $errors
    );

    foreach my $lock (@$locks) {
        my $lock_errors = [];
        my $enforcement = find_or_create_enforcement_from_lock_and_name(
            $lock,
            $LEGACY_ENFORCEMENT_NAME,
        );

        my $can_edit = can_edit_enforcement_as_user(
            $enforcement,
            $as_user,
            $lock_errors
        );

        foreach my $error (@$lock_errors) {
            push(@$errors, "add-users: $error");
        }
        return $errors if (scalar @$errors);

        if ($can_edit) {
            my $resulting_errors = add_users_to_enforcement(
                $users,
                $enforcement,
            );
            push(@$errors, @$resulting_errors);
            return $errors if (scalar @$errors);
        }
    }

    return $errors;
}

sub edit_locks_handle_remove_users_key($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['remove-users: You must define the as-user key.']
        if (! defined $as_user);

    my $errors = [];
    my $users = find_or_create_users_from_usernames(
        $data_manipulation_ref->{'remove-users'},
        $errors
    );

    my $user_ids = get_array_ref_from_ref($users, 'id');
    foreach my $lock (@$locks) {
        my $lock_errors = [];
        my $enforcements = get_enforcements_from_lock($lock);

        foreach my $enforcement (@$enforcements) {
            can_edit_enforcement_as_user(
                $enforcement,
                $as_user,
                $lock_errors
            );
        }

        if (scalar @$lock_errors) {
            foreach my $error (@$lock_errors) {
                push(@$errors, "remove-users: $error");
            }
        }

        else {
            foreach my $enforcement (@$enforcements) {
                remove_users_from_enforcement(
                    $users,
                    $enforcement,
                );
            }
        }
    }

    return $errors;
}

sub add_prs_to_enforcement($$)
{
    my $prs_ref               = shift;
    my $enforcement_ref       = shift;

    my $enforcement_id = $enforcement_ref->{'id'};

    my $errors = [];
    foreach my $cur_pr (@$prs_ref) {
        # Strip off scope information if any is passed.
        $cur_pr =~ s/-.*//;
        if ($cur_pr !~ /^[0-9]+$/) {
            push (@$errors, "Invalid PR: '$cur_pr'.");
        }
    }

    return $errors if (scalar @$errors);

    my $table_name = 'bl_link_pr_to_enforcement_is_allowed';
    foreach my $cur_pr (@$prs_ref) {
        my $link_ref = DBWrap::find_or_create_row_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => $table_name,
            'columns'  => {
                'enforcement_id' => $enforcement_id,
                'pr_number'      => $cur_pr,
            },
        });

        if (! defined $link_ref) {
            push (@$errors, <<ERROR);
Error finding or creating $table_name, PR: '$cur_pr'.
ERROR
        }
    }

    return $errors;
}

sub edit_locks_handle_add_prs_key($$$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['add-prs: You must define the as-user key.']
        if (! defined $as_user);

    my $prs_string = $data_manipulation_ref->{'add-prs'} || $EMPTY_STR;
    my $prs = get_array_ref_from_ref($prs_string);

    my $errors = [];
    foreach my $lock (@$locks) {
        my $lock_errors = [];
        my $enforcement = find_or_create_enforcement_from_lock_and_name(
            $lock,
            $LEGACY_ENFORCEMENT_NAME,
        );

        my $can_edit = can_edit_enforcement_as_user(
            $enforcement,
            $as_user,
            $lock_errors
        );

        foreach my $error (@$lock_errors) {
            push(@$errors, "add-prs: $error");
        }

        return $errors if (scalar @$errors);

        if ($can_edit) {
            my $resulting_errors = add_prs_to_enforcement(
                $prs,
                $enforcement,
            );

            push(@$errors, @$resulting_errors);
            return $errors if (scalar @$errors);
        }
    }

    return $errors;
}

sub edit_locks_handle_remove_prs_key($$)
{
    my $locks_ref             = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['remove-prs: You must define the as-user key.']
        if (! defined $as_user);

    my $prs_string = $data_manipulation_ref->{'remove-prs'} || $EMPTY_STR;
    my $prs = get_array_ref_from_ref($prs_string);

    my $errors = [];
    foreach my $lock_ref (@$locks_ref) {
        my $lock_errors = [];
        my $enforcements = get_enforcements_from_lock($lock_ref);
        my $enforcement_ids = get_array_ref_from_ref($enforcements, 'id');
        my $table_name = 'bl_link_pr_to_enforcement_is_allowed';
        my $links = DBWrap::get_rows_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => $table_name,
            'columns'  => {
                'enforcement_id' => $enforcement_ids,
                'pr_number'      => $prs,
            },
        });

        $enforcement_ids = get_array_ref_from_ref($links, 'enforcement_id');
        foreach my $enforcement_id (@$enforcement_ids) {
            can_edit_enforcement_as_user(
                { 'id' => $enforcement_id },
                $as_user,
                $lock_errors
            );
        }

        if (scalar @$lock_errors) {
            foreach my $error (@$lock_errors) {
                push(@$errors, "remove-prs: $error");
            }
        }

        else {
            my $link_ids = get_array_ref_from_ref($links, 'id');
            DBWrap::delete_rows_from_columns({
                'database' => $database_name,
                'schema'   => $schema_name,
                'table'    => $table_name,
                'columns'  => { 'id' => $link_ids, },
            });
        }
    }

    return $errors;
}

sub add_gate_keepers_to_enforcement($$)
{
    my $users_ref       = shift;
    my $enforcement_ref = shift;

    my $enforcement_id = $enforcement_ref->{'id'};

    foreach my $cur_user_ref (@$users_ref) {
        my $user_id = $cur_user_ref->{'id'};
        my $table_name = 'bl_link_user_to_enforcement_can_edit';
        my $link_ref = DBWrap::find_or_create_row_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => $table_name,
            'columns'  => {
                'enforcement_id' => $enforcement_id,
                'user_id'        => $user_id,
            },
        });

        die "Error finding or creating $table_name.\n"
            if (! defined $link_ref);

        $table_name = 'bl_link_user_to_enforcement_can_enable';
        $link_ref = DBWrap::find_or_create_row_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => $table_name,
            'columns'  => {
                'enforcement_id' => $enforcement_id,
                'user_id'        => $user_id,
            },
        });

        die "Error finding or creating $table_name.\n"
            if (! defined $link_ref);
    }
}

sub edit_locks_handle_add_gate_keepers_key($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['add-gate-keepers: You must define the as-user key.']
        if (! defined $as_user);

    my $errors = [];
    my $users = find_or_create_users_from_usernames(
        $data_manipulation_ref->{'add-gate-keepers'},
        $errors
    );

    if (is_user_an_admin($as_user)) {
        foreach my $lock (@$locks) {
            my $enforcement = find_or_create_enforcement_from_lock_and_name(
                $lock,
                $LEGACY_ENFORCEMENT_NAME,
            );
            add_gate_keepers_to_enforcement($users, $enforcement);
        }
    }

    else {
        push(@$errors, "add-gate-keepers: User '$as_user' is not an admin.");
    }

    return $errors;
}

sub edit_locks_handle_remove_gate_keepers_key($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['remove-gate-keepers: You must define the as-user key.']
        if (! defined $as_user);

    my $errors = [];
    my $users = find_or_create_users_from_usernames(
        $data_manipulation_ref->{'remove-gate-keepers'},
        $errors
    );

    if (is_user_an_admin($as_user)) {
        my $user_ids = get_array_ref_from_ref($users, 'id');
        foreach my $lock (@$locks) {
            my $enforcements = get_enforcements_from_lock($lock);
            my $enforcement_ids = get_array_ref_from_ref($enforcements, 'id');
            my $table_name = 'bl_link_user_to_enforcement_can_edit';
            DBWrap::delete_rows_from_columns({
                'database' => $database_name,
                'schema'   => $schema_name,
                'table'    => $table_name,
                'columns'  => {
                    'enforcement_id' => $enforcement_ids,
                    'user_id'        => $user_ids,
                },
            });

            $table_name = 'bl_link_user_to_enforcement_can_enable';
            DBWrap::delete_rows_from_columns({
                'database' => $database_name,
                'schema'   => $schema_name,
                'table'    => $table_name,
                'columns'  => {
                    'enforcement_id' => $enforcement_ids,
                    'user_id'        => $user_ids,
                },
            });
        }
    }
    else {
        push(@$errors, "remove-gate-keepers: User '$as_user' is not an admin.");
    }

    return $errors;
}

sub is_user_a_gate_keeper_on_lock($$)
{
    my $as_user = shift;
    my $lock    = shift;

    return 1 if (is_user_an_admin($as_user));

    my $results = DBWrap::get_rows_from_columns({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'view_lock_gate_keepers',
        'columns'  => {
            'gate_keeper' => $as_user,
            'lock_id'     => $lock->{'id'},
        },
    });

    return (scalar @$results);
}

sub edit_locks_handle_replace_message_key($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['replace-message: You must define the as-user key.']
        if (! defined $as_user);

    my $message = $data_manipulation_ref->{'replace-message'};

    my $errors = [];
    foreach my $lock (@$locks) {
        my $lock_id = $lock->{'id'};
        if (! is_user_a_gate_keeper_on_lock($as_user, $lock)) {
            push(@$errors, "replace-message: User '$as_user' is not a gatekeeper on Lock ID: '$lock_id'");
        }
    }

    if (scalar @$errors == 0) {
        my $lock_ids = get_array_ref_from_ref($locks, 'id');
        DBWrap::update_row({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'bl_lock',
            'ids_ref'  => { 'id' => $lock_ids, },
            'columns'  => { 'message' => $message, },
        });
    }

    return $errors;
}

my $edit_locks_set_status_dispatch_ref = {
    'open'       => \&edit_locks_set_status_handle_open,
    'restricted' => \&edit_locks_set_status_handle_restricted,
    'closed'     => \&edit_locks_set_status_handle_closed,
    $UNKNOWN_KEY => \&edit_locks_set_status_handle_unknown_key,
};

sub edit_locks_set_status_handle_unknown_key($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $status_value = $data_manipulation_ref->{'set-status'};

    my @valid_keys = grep { $_ ne $UNKNOWN_KEY }
        keys %$edit_locks_set_status_dispatch_ref;

    my $valid_values = join (', ', @valid_keys);
    my $error_message = <<ERROR;
Unknown status value '$status_value', valid values are: $valid_values
ERROR
    return [$error_message];
}

sub edit_locks_set_status_handle_open($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['set-status: You must define the as-user key.']
        if (! defined $as_user);

    my $errors = [];

    my $is_a_gate_keeper_on_any_lock = 0;
    foreach my $lock (@$locks) {
        if (is_user_a_gate_keeper_on_lock($as_user, $lock)) {
            $is_a_gate_keeper_on_any_lock = 1;
            last;
        }
    }

    if ($is_a_gate_keeper_on_any_lock) {
        my $lock_ids = get_array_ref_from_ref($locks, 'id');
        DBWrap::update_row({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'bl_lock',
            'ids_ref'  => { 'id' => $lock_ids, },
            'columns'  => {
                'is_open'   => 'true',
                'is_closed' => 'false',
            },
        });
    }

    else {
        push(@$errors, "set-status: User '$as_user' cannot enable any enforcements.");
    }

    return $errors;
}

sub edit_locks_set_status_handle_restricted($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['set-status: You must define the as-user key.']
        if (! defined $as_user);

    my $errors = [];
    my $lock_ids = get_array_ref_from_ref($locks, 'id');

    my $is_a_gate_keeper_on_any_lock = 0;
    foreach my $lock (@$locks) {
        if (is_user_a_gate_keeper_on_lock($as_user, $lock)) {
            $is_a_gate_keeper_on_any_lock = 1;
            last;
        }
    }

    if ($is_a_gate_keeper_on_any_lock) {
        DBWrap::update_row({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'bl_lock',
            'ids_ref'  => { 'id' => $lock_ids, },
            'columns'  => {
                'is_open'   => 'false',
                'is_closed' => 'false',
            },
        });

        foreach my $lock (@$locks) {
            my $lock_errors = [];
            my $enforcement = find_or_create_enforcement_from_lock_and_name(
                $lock,
                $LEGACY_ENFORCEMENT_NAME,
            );

            my $can_enable = can_enable_enforcement_as_user(
                $enforcement,
                $as_user,
                $lock_errors
            );

            if ($can_enable) {
                enable_enforcement($enforcement);
            }

            foreach my $lock_error (@$lock_errors) {
                push(@$errors, "set-status: $lock_error");
            }
        }
    }

    else {
        push(@$errors, "set-status: User '$as_user' cannot enable any enforcements.");
    }

    return $errors;
}

sub edit_locks_set_status_handle_closed($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['set-status: You must define the as-user key.']
        if (! defined $as_user);

    my $lock_ids = [];
    my $errors = [];
    foreach my $lock (@$locks) {
        my $lock_id = $lock->{'id'};
        my $enforcements = get_enforcements_from_lock($lock);
        my $can_enable_all_enforcements = 1;
        foreach my $enforcement (@$enforcements) {
            my $can_enable = can_enable_enforcement_as_user(
                $enforcement,
                $as_user,
                $errors
            );
            if (! $can_enable) {
                $can_enable_all_enforcements = 0;
                push(@$errors, "set-status: User '$as_user' cannot disable all enforcements on lock ID: $lock_id");
                last;
            }
        }
        if ($can_enable_all_enforcements) {
            push(@$lock_ids, $lock_id);
            foreach my $enforcement (@$enforcements) {
                disable_enforcement($enforcement);
            }
        }
    }

    if (scalar @$lock_ids) {
        DBWrap::update_row({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'bl_lock',
            'ids_ref'  => { 'id' => $lock_ids, },
            'columns'  => {
                'is_open'   => 'false',
                'is_closed' => 'true',
            },
        });
    }

    return $errors;
}

sub edit_locks_handle_set_status_key($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $status = lc( $data_manipulation_ref->{'set-status'} );

    my $subroutine_ref
        = $edit_locks_set_status_dispatch_ref->{$status}
        || $edit_locks_set_status_dispatch_ref->{$UNKNOWN_KEY};

    return &$subroutine_ref($locks, $data_manipulation_ref);
}

my $edit_locks_set_state_dispatch_ref = {
    'active'     => \&edit_locks_set_state_handle_active,
    'eol'        => \&edit_locks_set_state_handle_eol,
    $UNKNOWN_KEY => \&edit_locks_set_state_handle_unknown_key,
};

sub edit_locks_set_state_handle_unknown_key($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $state_value = $data_manipulation_ref->{'set-state'};

    my @valid_keys = grep { $_ ne $UNKNOWN_KEY }
        keys %$edit_locks_set_state_dispatch_ref;

    my $valid_values = join (', ', @valid_keys);
    my $error_message = <<ERROR;
Unknown state value '$state_value', valid values are: $valid_values
ERROR
    return [$error_message];
}

sub edit_locks_set_state_handle_active($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['set-state: You must define the as-user key.']
        if (! defined $as_user);

    my $errors = [];

    if (is_user_an_admin($as_user)) {
        my $lock_ids = get_array_ref_from_ref($locks, 'id');
        DBWrap::update_row({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'bl_lock',
            'ids_ref'  => { 'id' => $lock_ids, },
            'columns'  => { 'is_active' => 'true', },
        });
    }

    else {
        push(@$errors, "set-state: User '$as_user' is not an admin.");
    }

    return $errors;
}

sub edit_locks_set_state_handle_eol($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['set-state: You must define the as-user key.']
        if (! defined $as_user);

    my $errors = [];
    if (is_user_an_admin($as_user)) {
        my $lock_ids = get_array_ref_from_ref($locks, 'id');
        DBWrap::update_row({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'bl_lock',
            'ids_ref'  => { 'id' => $lock_ids, },
            'columns'  => { 'is_active' => 'false', },
        });
    }

    else {
        push(@$errors, "set-state: User '$as_user' is not an admin.");
    }

    return $errors;
}

sub edit_locks_handle_set_state_key($$)
{
    my $locks                 = shift;
    my $data_manipulation_ref = shift;

    my $state = lc( $data_manipulation_ref->{'set-state'} );

    my $subroutine_ref
        = $edit_locks_set_state_dispatch_ref->{$state}
        || $edit_locks_set_state_dispatch_ref->{$UNKNOWN_KEY};

    return &$subroutine_ref($locks, $data_manipulation_ref);
}

my $create_lock_data_dispatch_ref = {
    'allowed-users' => \&create_lock_handle_allowed_users_key,
    'allowed-prs'   => \&create_lock_handle_allowed_prs_key,
    'gate-keepers'  => \&create_lock_handle_gate_keepers_key,
    $UNKNOWN_KEY    => \&create_lock_handle_unknown_key,
};

sub create_lock($$)
{
    my $api_key_ref = shift;
    my $data_ref    = shift;

    my $errors = [];

    my $columns = {};

    my $as_user = $data_ref->{'as-user'};

    if (! is_user_an_admin($as_user)) {
        my $error = <<ERROR;
'$as_user' is not an admin.
You must be an admin to create a lock.
ERROR
        return {
            'errors'          => [$error],
            'http_error_code' => 403,
        };
    }

    my $data_dump = Data::Dumper::Dumper({
        'data_ref' => $data_ref,
    });

    my $audit_transaction_ref = start_audit_transaction(
        $api_key_ref,
        $data_dump,
        $as_user,
    );

    return $audit_transaction_ref
        if (exists $audit_transaction_ref->{$errors_key});

    $columns->{'name'} = $data_ref->{'name'}
        if (exists $data_ref->{'name'} && defined $data_ref->{'name'});

    $columns->{'message'} = $data_ref->{'message'}
        if (exists $data_ref->{'message'} && defined $data_ref->{'message'});

    $columns->{'is_active'} = $data_ref->{'is-active'}
        if (exists $data_ref->{'is-active'}
            && defined $data_ref->{'is-active'});

    $columns->{'is_open'} = $data_ref->{'is-open'}
        if (exists $data_ref->{'is-open'} && defined $data_ref->{'is-open'});

    $columns->{'is_closed'} = $data_ref->{'is-closed'}
        if (exists $data_ref->{'is-closed'}
            && defined $data_ref->{'is-closed'});

    $columns->{'old_lock'} = $data_ref->{'old-lock'}
        if (exists $data_ref->{'old-lock'}
            && defined $data_ref->{'old-lock'});

    $columns->{'old_release'} = $data_ref->{'old-release'}
        if (exists $data_ref->{'old-release'}
            && defined $data_ref->{'old-release'});

    $columns->{'grouped'} = $data_ref->{'grouped'}
        if (exists $data_ref->{'grouped'}
            && defined $data_ref->{'grouped'});

    my $lock_ref = DBWrap::insert_row({
        'database' => $database_name,
        'schema'   => $schema_name,
        'table'    => 'bl_lock',
        'columns'  => $columns,
    });

    foreach my $key (keys %$data_ref) {
        my $subroutine_ref
            = $create_lock_data_dispatch_ref->{$key}
            || $create_lock_data_dispatch_ref->{$UNKNOWN_KEY};

        my $resulting_errors = &$subroutine_ref(
            $lock_ref,
            $data_ref,
        );
        push(@$errors, @$resulting_errors);
    }

    if (scalar @$errors) {
        my $error_string = join("\n", @$errors);
        die $error_string;
    }

    my $locks_ref = get_locks({ 'lock_id' => $lock_ref });
    my @locks = @$locks_ref;

    $audit_transaction_ref->{'result'} = $locks[0];

    return end_audit_transaction($audit_transaction_ref);
}

=item create_lock_handle_unknown_key($)

If there is a key that is not handled return undef, nothing will be done.

=cut

sub create_lock_handle_unknown_key($$)
{
    return [];
}

# This is used when pulling locks from the old system.
sub create_lock_handle_allowed_users_key($$)
{
    my $lock                  = shift;
    my $data_ref              = shift;

    my $errors = [];
    my $users = find_or_create_users_from_usernames(
        $data_ref->{'allowed-users'},
        $errors
    );

    my $enforcement = find_or_create_enforcement_from_lock_and_name(
        $lock,
        $LEGACY_ENFORCEMENT_NAME,
    );

    add_users_to_enforcement(
        $users,
        $enforcement,
    );

    return [];
}

# This is used when pulling locks from the old system.
sub create_lock_handle_allowed_prs_key($$)
{
    my $lock                  = shift;
    my $data_ref              = shift;

    my $prs_string = $data_ref->{'allowed-prs'} || $EMPTY_STR;
    my $prs = get_array_ref_from_ref($prs_string);

    my $enforcement = find_or_create_enforcement_from_lock_and_name(
        $lock,
        $LEGACY_ENFORCEMENT_NAME,
    );

    add_prs_to_enforcement(
        $prs,
        $enforcement,
    );

    return [];
}

sub create_lock_handle_gate_keepers_key($$)
{
    my $lock                  = shift;
    my $data_ref              = shift;

    my $errors = [];
    my $users = find_or_create_users_from_usernames(
        $data_ref->{'gate-keepers'},
        $errors
    );

    my $enforcement = find_or_create_enforcement_from_lock_and_name(
        $lock,
        $LEGACY_ENFORCEMENT_NAME,
    );
    add_gate_keepers_to_enforcement($users, $enforcement);

    return [];
}

sub get_enforcements($)
{
    my $criteria_ref = shift;

    my $columns = {};

    # Handled Keys
    $columns->{'id'} = get_array_ref_from_ref($criteria_ref->{'id'}, 'id');

    my $results = [];

    if (scalar keys %$columns) {
        $results = DBWrap::get_rows_from_columns({
            'database' => $database_name,
            'schema'   => $schema_name,
            'table'    => 'view_enforcements',
            'columns'  => $columns,
        });
    }

    return $results;
}

my $edit_enforcements_data_manipulation_dispatch_ref = {
    'add-allowed-users'
        => \&edit_enforcements_handle_add_allowed_users_key,

    'remove-allowed-users'
        => \&edit_enforcements_handle_remove_allowed_users_key,

    'add-allowed-prs'
        => \&edit_enforcements_handle_add_allowed_prs_key,

    'remove-allowed-prs'
        => \&edit_enforcements_handle_remove_allowed_prs_key,

    'add-users-who-can-enable'
        => \&edit_enforcements_handle_add_users_who_can_enable_key,

    'remove-users-who-can-enable'
        => \&edit_enforcements_handle_remove_users_who_can_enable_key,

    'add-users-who-can-edit'
        => \&edit_enforcements_handle_add_users_who_can_edit_key,

    'remove-users-who-can-edit'
        => \&edit_enforcements_handle_remove_users_who_can_edit_key,

    'name'
        => \&edit_enforcements_handle_name_key,

    'is_enabled'
        => \&edit_enforcements_handle_is_enabled_key,

    'as-user'
        => \&edit_enforcements_ignore_key,

    $UNKNOWN_KEY
        => \&edit_enforcements_ignore_key,
};

sub edit_enforcements_ignore_key($$)
{
    return [];
}

sub edit_enforcements($$$)
{
    my $api_key_ref           = shift;
    my $enforcements_ref      = shift;
    my $data_manipulation_ref = shift;

    return if (scalar @$enforcements_ref == 0);

    my $as_user = $data_manipulation_ref->{'as-user'};
    my $data_dump = Data::Dumper::Dumper({
        'enforcements'          => $enforcements_ref,
        'data_manipulation_ref' => $data_manipulation_ref,
    });

    my $audit_transaction_ref = start_audit_transaction(
        $api_key_ref,
        $data_dump,
        $as_user,
    );

    return $audit_transaction_ref
        if (exists $audit_transaction_ref->{$errors_key});

    foreach my $key (keys %$data_manipulation_ref) {
        my $subroutine_ref
            = $edit_enforcements_data_manipulation_dispatch_ref->{$key}
            || $edit_enforcements_data_manipulation_dispatch_ref->{$UNKNOWN_KEY};

        my $resulting_errors = &$subroutine_ref(
            $enforcements_ref,
            $data_manipulation_ref
        );

        if (scalar @$resulting_errors) {
            add_errors(
                $audit_transaction_ref,
                400,
                @$resulting_errors,
            );
        }
    }

    return $audit_transaction_ref
        if (exists $audit_transaction_ref->{$errors_key});

    $audit_transaction_ref->{'result'}
        = get_enforcements({ 'id' => $enforcements_ref });

    return end_audit_transaction($audit_transaction_ref);
}

sub edit_enforcements_handle_add_allowed_users_key($$)
{
    my $enforcements          = shift;
    my $data_manipulation_ref = shift;

    my $as_user               = $data_manipulation_ref->{'as-user'};

    return ['add-users: You must define the as-user key.']
        if (! defined $as_user);

    my $errors = [];
    my $users = find_or_create_users_from_usernames(
        $data_manipulation_ref->{'add-allowed-users'},
        $errors
    );

    foreach my $enforcement (@$enforcements) {
        my $enforcement_errors = [];

        my $can_edit = can_edit_enforcement_as_user(
            $enforcement,
            $as_user,
            $enforcement_errors
        );

        foreach my $error (@$enforcement_errors) {
            push(@$errors, "add-allowed-users: $error");
        }
        return $errors if (scalar @$errors);

        if ($can_edit) {
            my $resulting_errors = add_users_to_enforcement(
                $users,
                $enforcement,
            );
            push(@$errors, @$resulting_errors);
            return $errors if (scalar @$errors);
        }
    }

    return $errors;
}

sub edit_enforcements_handle_remove_allowed_users_key($$)
{
    my $enforcements          = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['remove-allowed-users: You must define the as-user key.']
        if (! defined $as_user);

    my $errors = [];
    my $users = find_or_create_users_from_usernames(
        $data_manipulation_ref->{'remove-allowed-users'},
        $errors
    );

    my $user_ids = get_array_ref_from_ref($users, 'id');
    my $enforcement_errors = [];

    foreach my $enforcement (@$enforcements) {
        can_edit_enforcement_as_user(
            $enforcement,
            $as_user,
            $enforcement_errors
        );
    }

    if (scalar @$enforcement_errors) {
        foreach my $error (@$enforcement_errors) {
            push(@$errors, "remove-allowed-users: $error");
        }
    }

    else {
        foreach my $enforcement (@$enforcements) {
            remove_users_from_enforcement(
                $users,
                $enforcement,
            );
        }
    }

    return $errors;
}

sub edit_enforcements_handle_add_allowed_prs_key($$)
{
    my $enforcements          = shift;
    my $data_manipulation_ref = shift;

    my $as_user = $data_manipulation_ref->{'as-user'};

    return ['add-allowed-prs: You must define the as-user key.']
        if (! defined $as_user);

    my $prs_string = $data_manipulation_ref->{'add-allowed-prs'}
        || $EMPTY_STR;

    my $prs = get_array_ref_from_ref($prs_string);

    my $errors = [];
    foreach my $enforcement (@$enforcements) {
        my $enforcement_errors = [];

        my $can_edit = can_edit_enforcement_as_user(
            $enforcement,
            $as_user,
            $enforcement_errors
        );

        foreach my $error (@$enforcement_errors) {
            push(@$errors, "add-allowed-prs: $error");
        }

        return $errors if (scalar @$errors);

        if ($can_edit) {
            my $resulting_errors = add_prs_to_enforcement(
                $prs,
                $enforcement,
            );

            push(@$errors, @$resulting_errors);
            return $errors if (scalar @$errors);
        }
    }

    return $errors;
}

sub edit_enforcements_handle_remove_allowed_prs_key($$$)
{
}

sub edit_enforcements_handle_add_users_who_can_enable_key($$$)
{
}

sub edit_enforcements_handle_remove_users_who_can_enable_key($$$)
{
}

sub edit_enforcements_handle_add_users_who_can_edit_key($$$)
{
}

sub edit_enforcements_handle_remove_users_who_can_edit_key($$$)
{
}

sub edit_enforcements_handle_name_key($$$)
{
}

sub edit_enforcements_handle_is_enabled_key($$$)
{
}

sub parse_data_from_audit_event($$)
{
    my $raw_data        = shift;
    my $expected_values = shift;

    my @values = ();
    if ($raw_data =~ /\((.*)\)/) {
        @values = split(',', $1);
    }

    return (scalar @values == $expected_values) ? @values : undef;
}

# The parse X data from audit event subroutines are separated so if the
# columns in the tables change we can support multiple audit formats here.
sub parse_data_link_pr_to_enforcement_is_allowed($)
{
    my $raw_data = shift;
    return parse_data_from_audit_event($raw_data, 3);
}

sub parse_data_link_user_to_enforcement_is_allowed($)
{
    my $raw_data = shift;
    return parse_data_from_audit_event($raw_data, 3);
}

sub parse_data_link_user_to_enforcement_can_enable($)
{
    my $raw_data = shift;
    return parse_data_from_audit_event($raw_data, 3);
}

sub parse_data_link_user_to_enforcement_can_edit($)
{
    my $raw_data = shift;
    return parse_data_from_audit_event($raw_data, 3);
}

sub parse_lock_data_from_audit_event($)
{
    my $raw_data = shift;
    return parse_data_from_audit_event($raw_data, 9);
}

sub parse_enforcement_data_from_audit_event($)
{
    my $raw_data = shift;
    return parse_data_from_audit_event($raw_data, 3);
}

sub bl_link_pr_to_enforcement_is_allowed_insert_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $pr_number, $enforcement_id)
        = parse_data_link_pr_to_enforcement_is_allowed(
            $audit_event->{'new_data'}
    );

    my $result = '[Error]: Unrecognized link_pr_to_enforcement_insert format';
    if (defined $link_id) {
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};

        $result = "Added PR $pr_number to enforcement: '$name'.";
    }

    return $result;
}

sub bl_link_pr_to_enforcement_is_allowed_update_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $pr_number, $enforcement_id)
        = parse_data_link_pr_to_enforcement_is_allowed(
            $audit_event->{'new_data'}
    );

    my $result = '[Error]: Unrecognized link_pr_to_enforcement_update format';
    if (defined $link_id) {
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};

        $result = "Changed PR $pr_number on enforcement: '$name'.";
    }

    return $result;
}

sub bl_link_pr_to_enforcement_is_allowed_delete_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $pr_number, $enforcement_id)
        = parse_data_link_pr_to_enforcement_is_allowed(
            $audit_event->{'old_data'}
    );

    my $result = '[Error]: Unrecognized link_pr_to_enforcement_delete format';
    if (defined $link_id) {
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};

        $result = "Removed PR $pr_number from enforcement: '$name'.";
    }

    return $result;
}

sub bl_link_user_to_enforcement_is_allowed_insert_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $user_id, $enforcement_id)
        = parse_data_link_user_to_enforcement_is_allowed(
            $audit_event->{'new_data'}
    );

    my $result = '[Error]: Unrecognized link_user_to_enforcement_insert format';
    if (defined $link_id) {
        my $user_ref = get_user_from_id($user_id);
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};
        my $username        = $user_ref->{'name'};

        $result = <<MESSAGE;
Added user '$username' to allowed users on enforcement: '$name'.
MESSAGE
    }

    return $result;
}

sub bl_link_user_to_enforcement_is_allowed_update_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $user_id, $enforcement_id)
        = parse_data_link_user_to_enforcement_is_allowed(
            $audit_event->{'new_data'}
    );

    my $result = '[Error]: Unrecognized link_user_to_enforcement_update format';
    if (defined $link_id) {
        my $user_ref = get_user_from_id($user_id);
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};
        my $username        = $user_ref->{'name'};

        $result = <<MESSAGE;
Added user '$username' to allowed users on enforcement: '$name'.
MESSAGE
    }

    return $result;
}

sub bl_link_user_to_enforcement_is_allowed_delete_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $user_id, $enforcement_id)
        = parse_data_link_user_to_enforcement_is_allowed(
            $audit_event->{'old_data'}
    );

    my $result = '[Error]: Unrecognized link_user_to_enforcement_delete format';
    if (defined $link_id) {
        my $user_ref = get_user_from_id($user_id);
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};
        my $username        = $user_ref->{'name'};

        $result = <<MESSAGE;
Removed user '$username' from allowed users on enforcement: '$name'.
MESSAGE
    }

    return $result;
}

sub bl_link_user_to_enforcement_can_enable_insert_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $user_id, $enforcement_id)
        = parse_data_link_user_to_enforcement_can_enable(
            $audit_event->{'new_data'}
    );

    my $result = '[Error]: Unrecognized can_enable_enforcement_insert format';
    if (defined $link_id) {
        my $user_ref = get_user_from_id($user_id);
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};
        my $username        = $user_ref->{'name'};

        $result = <<MESSAGE;
User '$username' can now enable enforcement: '$name'.
MESSAGE
    }

    return $result;
}

sub bl_link_user_to_enforcement_can_enable_update_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $user_id, $enforcement_id)
        = parse_data_link_user_to_enforcement_can_enable(
            $audit_event->{'new_data'}
    );

    my $result = '[Error]: Unrecognized can_enable_enforcement_update format';
    if (defined $link_id) {
        my $user_ref = get_user_from_id($user_id);
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};
        my $username        = $user_ref->{'name'};

        $result = <<MESSAGE;
User '$username' can now enable enforcement: '$name'.
MESSAGE
    }

    return $result;
}

sub bl_link_user_to_enforcement_can_enable_delete_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $user_id, $enforcement_id)
        = parse_data_link_user_to_enforcement_can_enable(
            $audit_event->{'old_data'}
    );

    my $result = '[Error]: Unrecognized can_enable_enforcement_delete format';
    if (defined $link_id) {
        my $user_ref = get_user_from_id($user_id);
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};
        my $username        = $user_ref->{'name'};

        $result = <<MESSAGE;
User '$username' can no longer enable enforcement: '$name'.
MESSAGE
    }

    return $result;
}

sub bl_link_user_to_enforcement_can_edit_insert_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $user_id, $enforcement_id)
        = parse_data_link_user_to_enforcement_can_edit(
            $audit_event->{'new_data'}
    );

    my $result = '[Error]: Unrecognized can_edit_enforcement_insert format';
    if (defined $link_id) {
        my $user_ref = get_user_from_id($user_id);
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};
        my $username        = $user_ref->{'name'};

        $result = <<MESSAGE;
User '$username' can now edit enforcement: '$name'.
MESSAGE
    }

    return $result;
}

sub bl_link_user_to_enforcement_can_edit_update_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $user_id, $enforcement_id)
        = parse_data_link_user_to_enforcement_can_edit(
            $audit_event->{'new_data'}
    );

    my $result = '[Error]: Unrecognized can_edit_enforcement_update format';
    if (defined $link_id) {
        my $user_ref = get_user_from_id($user_id);
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};
        my $username        = $user_ref->{'name'};

        $result = <<MESSAGE;
User '$username' can now edit enforcement: '$name'.
MESSAGE
    }

    return $result;
}

sub bl_link_user_to_enforcement_can_edit_delete_print_sub($)
{
    my $audit_event = shift;
    my ($link_id, $user_id, $enforcement_id)
        = parse_data_link_user_to_enforcement_can_edit(
            $audit_event->{'old_data'}
    );

    my $result = '[Error]: Unrecognized can_edit_enforcement_delete format';
    if (defined $link_id) {
        my $user_ref = get_user_from_id($user_id);
        my @enforcements = @{ get_enforcements({
            'id' => $enforcement_id
        }) };

        my $enforcement_ref = $enforcements[0];
        my $name            = $enforcement_ref->{'name'};
        my $username        = $user_ref->{'name'};

        $result = <<MESSAGE;
User '$username' can no longer edit enforcement: '$name'.
MESSAGE
    }

    return $result;
}

sub bl_lock_insert_print_sub($)
{
    my $audit_event = shift;

    my ($id,
        $name,
        $message,
        $is_active,
        $is_open,
        $old_lock,
        $old_release,
        $grouped,
        $is_closed,
    ) = parse_lock_data_from_audit_event($audit_event->{'new_data'});

    my $result = '[Error]: Unrecognized lock_insert_print format';
    if (defined $id) {
        $result = <<MESSAGE;
Created lock '$name' with the following message:
$message
MESSAGE
    }

    return $result;
}

sub bl_lock_update_print_sub($)
{
    my $audit_event = shift;

    my ($id,
        $name,
        $message,
        $is_active,
        $is_open,
        $old_lock,
        $old_release,
        $grouped,
        $is_closed,
    ) = parse_lock_data_from_audit_event($audit_event->{'new_data'});

    my $result = '[Error]: Unrecognized lock_update_print format';
    if (defined $id) {
        $result = <<MESSAGE;
Changed lock '$name' with the following message:
$message
MESSAGE
    }

    return $result;
}

sub bl_lock_delete_print_sub($)
{
    my $audit_event = shift;

    my ($id,
        $name,
        $message,
        $is_active,
        $is_open,
        $old_lock,
        $old_release,
        $grouped,
        $is_closed,
    ) = parse_lock_data_from_audit_event($audit_event->{'old_data'});

    my $result = '[Error]: Unrecognized lock_delete_print format';
    if (defined $id) {
        $result = "Deleted lock '$name'.";
    }

    return $result;
}

sub bl_enforcement_insert_print_sub($)
{
    my $audit_event = shift;

    my ($id,
        $name,
        $is_enabled,
    ) = parse_enforcement_data_from_audit_event($audit_event->{'new_data'});

    my $result = '[Error]: Unrecognized enforcement_insert_print format';
    if (defined $id) {
        $name =~ s/(^"|"$)//g;
        $result = "Created enforcement '$name'.";
    }

    return $result;
}

sub bl_enforcement_update_print_sub($)
{
    my $audit_event = shift;

    my ($id,
        $name,
        $is_enabled,
    ) = parse_enforcement_data_from_audit_event($audit_event->{'new_data'});

    my $result = '[Error]: Unrecognized enforcement_update_print format';
    if (defined $id) {
        $name =~ s/(^"|"$)//g;
        $result = "Changed enforcement '$name'.";
    }

    return $result;
}

sub bl_enforcement_delete_print_sub($)
{
    my $audit_event = shift;

    my ($id,
        $name,
        $is_enabled,
    ) = parse_enforcement_data_from_audit_event($audit_event->{'new_data'});

    my $result = '[Error]: Unrecognized enforcement_delete_print format';
    if (defined $id) {
        $name =~ s/(^"|"$)//g;
        $result = "Deleted enforcement '$name'.";
    }

    return $result;
}

my $get_audit_trail_dispatch_table = {
    'lock'        => \&get_audit_trail_locks,
    'enforcement' => \&get_audit_trail_enforcements,
    $UNKNOWN_KEY  => \&get_audit_trail_unknown_object,
};

sub pull_audit_events($$$$$)
{
    my $table_name       = shift;
    my $regex            = shift;
    my $insert_print_sub = shift;
    my $update_print_sub = shift;
    my $delete_print_sub = shift;

    my $sql = <<SQL;
SELECT *
FROM   $schema_name.view_audit_trail
WHERE  table_name = '$table_name'
    AND ( new_data similar to E'$regex'
          OR  old_data similar to E'$regex'
    )
SQL

    my $audit_events = DBWrap::sql_returning_rows({
        'database' => $database_name,
        'sql'      => $sql,
    });

    my $audit_transactions = {};
    foreach my $audit_event (@$audit_events) {
        my $audit_transaction_id = $audit_event->{'audit_transaction_id'};
        my $username             = $audit_event->{'username'            };
        my $on_behalf_of         = $audit_event->{'on_behalf_of'        };
        my $date                 = $audit_event->{'end_timestamp'       };
        my $action               = $audit_event->{'action'              };
        my $new_data             = $audit_event->{'new_data'            };
        my $old_data             = $audit_event->{'old_data'            };

        my $transaction_details
            = $audit_transactions->{$audit_transaction_id};

        if (! defined $transaction_details) {
            $transaction_details = {
                'username'     => $username,
                'on_behalf_of' => $on_behalf_of,
                'date'         => $date,
                'actions'      => [],
            };
        }
        elsif ($transaction_details->{'date'} lt $date) {
            $transaction_details->{'date'} = $date;
        }

        my $actions_ref = $transaction_details->{'actions'};

        # Print messages nicely.
        if ($action eq 'INSERT') {
            push(@$actions_ref, &$insert_print_sub($audit_event));
        }
        elsif ($action eq 'UPDATE') {
            push(@$actions_ref, &$update_print_sub($audit_event));
        }
        elsif ($action eq 'DELETE') {
            push(@$actions_ref, &$delete_print_sub($audit_event));
        }

        $audit_transactions->{$audit_transaction_id} = $transaction_details;
    }

    return $audit_transactions;
}

sub combine_audit_trail_events($$)
{
    my $audit_trail_ref = shift;
    my $partial_trail_ref = shift;

    foreach my $audit_transaction_id (keys %$partial_trail_ref) {
        my $audit_event = $audit_trail_ref->{$audit_transaction_id};
        my $partial_event = $partial_trail_ref->{$audit_transaction_id};

        if (! defined $audit_event) {
            $audit_trail_ref->{$audit_transaction_id}
                = $partial_trail_ref->{$audit_transaction_id};
        }
        else {
            my $audit_event_actions   = $audit_event->{'actions'} || [];
            my $partial_event_actions = $partial_event->{'actions'} || [];
            push(@$audit_event_actions, @$partial_event_actions);
            $audit_event->{'actions'} = $audit_event_actions;
        }
    }
}

sub get_audit_trail_locks($)
{
    my $inputs_ref = shift;

    my $lock_ids_ref = get_array_ref_from_ref($inputs_ref, 'id');
    my $locks_ref    = get_locks({ 'lock_id' => $inputs_ref });

    my $ids_string = join('|', @$lock_ids_ref);
    my $audit_trail = {};

    my $regex = "\\\\(($ids_string),%";

    my $audit_events = pull_audit_events(
        'bl_lock',
        $regex,
        \&bl_lock_insert_print_sub,
        \&bl_lock_update_print_sub,
        \&bl_lock_delete_print_sub,
    );

    combine_audit_trail_events($audit_trail, $audit_events);

    foreach my $lock_ref (@$locks_ref) {
        my $enforcements_ref = get_enforcements_from_lock($lock_ref);
        $audit_events = get_audit_trail_enforcements($enforcements_ref);

        combine_audit_trail_events($audit_trail, $audit_events);
    }

    return $audit_trail;
}

sub get_audit_trail_enforcements($)
{
    my $inputs_ref = shift;

    my $enforcement_ids_ref = get_array_ref_from_ref($inputs_ref, 'id');
    my $enforcements_ref
        = get_enforcements({ 'id' => $enforcement_ids_ref });

    my $ids_string = join('|', @$enforcement_ids_ref);
    my $audit_trail = {};

    my $regex = "\\\\(($ids_string),%";
    my $audit_events = pull_audit_events(
        'bl_enforcement',
        $regex,
        \&bl_enforcement_insert_print_sub,
        \&bl_enforcement_update_print_sub,
        \&bl_enforcement_delete_print_sub,
    );

    combine_audit_trail_events($audit_trail, $audit_events);

    $regex = "%,($ids_string)\\\\)";
    $audit_events = pull_audit_events(
        'bl_link_pr_to_enforcement_is_allowed',
        $regex,
        \&bl_link_pr_to_enforcement_is_allowed_insert_print_sub,
        \&bl_link_pr_to_enforcement_is_allowed_update_print_sub,
        \&bl_link_pr_to_enforcement_is_allowed_delete_print_sub,
    );

    combine_audit_trail_events($audit_trail, $audit_events);

    $audit_events = pull_audit_events(
        'bl_link_user_to_enforcement_is_allowed',
        $regex,
        \&bl_link_user_to_enforcement_is_allowed_insert_print_sub,
        \&bl_link_user_to_enforcement_is_allowed_update_print_sub,
        \&bl_link_user_to_enforcement_is_allowed_delete_print_sub,
    );

    combine_audit_trail_events($audit_trail, $audit_events);

    $audit_events = pull_audit_events(
        'bl_link_user_to_enforcement_can_enable',
        $regex,
        \&bl_link_user_to_enforcement_can_enable_insert_print_sub,
        \&bl_link_user_to_enforcement_can_enable_update_print_sub,
        \&bl_link_user_to_enforcement_can_enable_delete_print_sub,
    );

    combine_audit_trail_events($audit_trail, $audit_events);

    $audit_events = pull_audit_events(
        'bl_link_user_to_enforcement_can_edit',
        $regex,
        \&bl_link_user_to_enforcement_can_edit_insert_print_sub,
        \&bl_link_user_to_enforcement_can_edit_update_print_sub,
        \&bl_link_user_to_enforcement_can_edit_delete_print_sub,
    );

    combine_audit_trail_events($audit_trail, $audit_events);

    return $audit_trail;
}

sub get_audit_trail_unknown_object($)
{
    return [];
}

sub get_audit_trail($$) {
    my $object_type = shift;
    my $object_id   = shift;

    my $subroutine_ref = $get_audit_trail_dispatch_table->{$object_type} ||
        $get_audit_trail_dispatch_table->{$UNKNOWN_KEY};

    return &$subroutine_ref($object_id);
}

=back

=cut

1;
