
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

DBWrap.pm - Collection of wrappers for DBI Methods.

=head1 SYNOPSIS

use DBWrap;

=head1 Subroutines

=over

=cut

use strict;
use warnings;

use DBI;
use DBServers;

package DBWrap;

my $EMPTY_STR   = q{};
my $UNKNOWN_KEY = '__UNKNOWN_KEY__';

# Multiple database servers
my @server_order = undef;
my $server       = undef;

# Multiple database connections
my $readonly_handles = undef;

# Write connection
my $writable_handles = undef;

my $errstr = $EMPTY_STR;

my $special_values = {
    'now()'      => sub { return 'now()' },
    $EMPTY_STR   => sub { return 'null'  },
    $UNKNOWN_KEY => sub { my $value = shift; return sql_quote($value)  },
};

# Locks
my $locks = {};

sub server()
{
    return $server;
}

sub server_order()
{
    return @server_order;
}

sub readonly_handles()
{
    return defined $readonly_handles ? { %$readonly_handles } : undef;
}

sub writable_handles()
{
    return defined $writable_handles ? { %$writable_handles } : undef;
}

sub next_readonly_server()
{
    $server = scalar @server_order ? shift(@server_order) : undef;
    if (defined $readonly_handles) {
        my @databases = keys %$readonly_handles;
        close_databases($readonly_handles);
        open_readonly_databases(\@databases);
    }
}

=item connect($)

Connect to the databases specified in the argument hash reference.

=cut

sub handle_connection_error($)
{
    $errstr = shift;
    chomp($errstr);
    return undef;
}

sub connect($)
{
    my $args_ref   = shift;
    my $subroutine = (caller(0))[3];

    my $host = $args_ref->{'host'}
        || die "$subroutine - key host not defined.";

    my $user = $args_ref->{'user'}
        || die "$subroutine - key user not defined.";

    my $pass          = $args_ref->{'pass'     } || $EMPTY_STR;
    my $databases_ref = $args_ref->{'databases'} || [];

    my $database_handles = {};
    foreach my $db (@$databases_ref) {
        $database_handles->{$db} = DBI->connect(
            "DBI:Pg:dbname=$db;host=$host;sslmode=prefer",
            $user,
            $pass,
            { 'PrintError' => 0 }
        ) or return handle_connection_error($DBI::errstr);
    }

    return $database_handles;
}

sub open_readonly_databases($)
{
    my $databases = shift;
    open_databases($databases, 0);
}

sub open_writable_databases($)
{
    my $databases = shift;
    open_databases($databases, 1);
}

sub open_databases($$)
{
    my $databases     = shift;
    my $writable_flag = shift;
    my $sub           = (caller(0))[3];

    return if (! defined $server);

    if ($writable_flag) {
        die "$sub - Writable flag was not set upon initialization."
            if (! defined $writable_handles);

        my $new_handles = DBWrap::connect({
            'host'      => $DBServers::readwrite_host,
            'user'      => $DBServers::readwrite_user,
            'pass'      => $DBServers::readwrite_pass,
            'databases' => $databases,
        });

        die "$sub - Was not able to connect to the writable database server."
            if (! defined $new_handles);

        $writable_handles = { %$writable_handles, %$new_handles };
    }

    die "$sub - DBWrap::init must be called first."
        if (! defined $readonly_handles);

    my $new_handles = {};
    my $connected = 0;
    do {
        $new_handles = DBWrap::connect({
            'host'      => $server,
            'user'      => $DBServers::readonly_user,
            'pass'      => $DBServers::readonly_pass,
            'databases' => $databases,
        });

        if (defined $new_handles) {
            $connected = 1;
        } else {
            next_readonly_server();
            die "$sub - Could not connect to database servers: $errstr"
                if (! defined $server);
        }
    } while (! $connected);

    $readonly_handles = { %$readonly_handles, %$new_handles };
}

sub close_databases($)
{
    my $handles_ref = shift;
    foreach my $dbname (keys %$handles_ref) {
        $handles_ref->{$dbname}->disconnect();
        delete $handles_ref->{$dbname};
    }
}

sub init
{
    my $inputs_ref    = shift;
    my $sub           = (caller(0))[3];

    my $databases     = $inputs_ref->{'databases'} || [];
    my $writable_flag = $inputs_ref->{'writable' } || 0;

    @server_order = DBServers::get_server_order();
    next_readonly_server();
    die "$sub - No pingable database servers found." if (! defined $server);

    close_databases($readonly_handles) if (defined $readonly_handles);
    $readonly_handles = {};
    open_readonly_databases($databases);

    if ($writable_flag) {
        close_databases($writable_handles) if (defined $writable_handles);
        $writable_handles = {};
        open_writable_databases($databases);
    } else {
        $writable_handles = undef;
    }
}

sub sql_returning_rows($)
{
    my $args     = shift;
    my $sub      = (caller(0))[3];

    my $database = $args->{'database'} || die <<ERROR;
$sub - You must define key database.
ERROR

    my $sql = $args->{'sql'} || die <<ERROR;
$sub - You must define key sql.
ERROR

    my $use_writable_handle = $args->{'use_writable_handle'} || 0;

    my $results = undef;
    if (! $use_writable_handle) {
        do {
            my $dbh = $readonly_handles->{$database}
                or die "$sub - not connected to database '$database'";

            $results = $dbh->selectall_arrayref($sql, { 'Slice' => {} });
            if (! defined $results) {
                $errstr .= "$server - " . $dbh->errstr . "\n";
                next_readonly_server();
                die "$sub - $errstr - SQL failed:\n$sql"
                    if (! defined $server);
            }
        } while (! defined $results);
        $errstr = $EMPTY_STR;
    } else {
        die "$sub - Writable flag was not set upon initialization."
            if (! defined $writable_handles);

        my $dbh = $writable_handles->{$database}
            or die "$sub - not connected to database '$database'";

        $results = $dbh->selectall_arrayref($sql, { 'Slice' => {} })
            || die "$sub - " . $dbh->errstr . " - SQL failed:\n$sql";
    }
    
    return $results;
}

sub sql_quote($)
{
    my $raw_string = shift;

    my $escape = '$escape$';

    return $escape . $raw_string . $escape;
}

sub construct_clause($$)
{
    my $column_string = shift;
    my $check_ref     = shift;

    my $result = $EMPTY_STR;

    if (ref $check_ref eq $EMPTY_STR) {
        my $value = $check_ref;
        my $sub_ref = $special_values->{$value}
            || $special_values->{$UNKNOWN_KEY};

        $value  = &$sub_ref($value);
        $result = "$column_string = $value";
    }

    elsif (ref $check_ref eq 'ARRAY') {
        my @value_list = ();
        foreach my $value (@$check_ref) {
            my $sub_ref = $special_values->{$value}
                || $special_values->{$UNKNOWN_KEY};

            push(@value_list, &$sub_ref($value));
        }
        my $list_string = join(', ', @value_list);
        $result = "$column_string in ($list_string)";
    }

    return $result;
}

sub get_column_equals_value_clauses($)
{
    my $args        = shift;
    my $sub         = (caller(0))[3];

    my $schema      = $args->{'schema' } || 'public';
    my $table       = $args->{'table'  } || die "$sub - key table undefined.";
    my $columns_ref = $args->{'columns'} || {};

    my $database = $args->{'database'}
        || die "$sub - key database undefined.";

    my @clauses = ();
    foreach my $column (keys %$columns_ref) {
        my $column_string = "$database.$schema.$table.$column";
        my $check_ref = $columns_ref->{$column};
        my $clause = $EMPTY_STR;

        if (ref $check_ref eq 'HASH') {
            my $negation = exists $check_ref->{'negation'}
                           ? $check_ref->{'negation'}
                           : 0
                           ;

            my $value_ref = $check_ref->{'values'};
            $clause = construct_clause($column_string, $value_ref);
            $clause = 'not ' . $clause if ($negation);
        }
        else {
            $clause = construct_clause($column_string, $check_ref);
        }

        push(@clauses, $clause);
    }

    return @clauses;
}

sub get_where_clause($)
{
    my $args        = shift;
    my $sub         = (caller(0))[3];

    my $schema      = $args->{'schema' } || 'public';
    my $table       = $args->{'table'  } || die "$sub - key table undefined.";
    my $columns_ref = $args->{'columns'} || {};

    my $database = $args->{'database'}
        || die "$sub - key database undefined.";

    my $where_clause = $EMPTY_STR;

    my @clauses = get_column_equals_value_clauses($args);

    $where_clause = "WHERE " . join(' and ', @clauses) if (scalar @clauses);
    $where_clause =~ s/= null/is null/g;

    return $where_clause;
}

sub get_order_clause($)
{
    my $args        = shift;
    my $sub         = (caller(0))[3];

    my $schema      = $args->{'schema'} || 'public';
    my $table       = $args->{'table' } || die "$sub - key table undefined.";
    my $order_ref   = $args->{'order' } || {};

    my $database = $args->{'database'}
        || die "$sub - key database undefined.";

    my $order_clause = $EMPTY_STR;

    my @clauses = ();
    my $columns_ref = $order_ref->{'columns'} || [];
    foreach my $column (@$columns_ref) {
        push(@clauses, "$database.$schema.$table.$column");
    }

    return $order_clause if (! scalar @clauses);

    $order_clause = "ORDER BY " . join(', ', @clauses);

    my $desc = $order_ref->{'desc'} || 0;
    $order_clause .= " DESC" if ($desc);

    return $order_clause;
}

sub get_limit_clause($)
{
    my $args   = shift;
    my $limit  = $args->{'limit' };
    my $offset = $args->{'offset'};

    my $clause = $EMPTY_STR;
    if (defined $limit) {
        $clause .= "LIMIT $limit";
        $clause .= " OFFSET $offset" if (defined $offset);
    }

    return $clause;
}

sub get_set_clause($)
{
    my $args        = shift;
    my $sub         = (caller(0))[3];

    my $schema      = $args->{'schema' } || 'public';
    my $table       = $args->{'table'  } || die "$sub - key table undefined.";
    my $columns_ref = $args->{'columns'} || {};

    my $database = $args->{'database'}
        || die "$sub - key database undefined.";

    my $set_clause = $EMPTY_STR;

    my @clauses = get_column_equals_value_clauses($args);

    $set_clause = "SET " . join(', ', @clauses) if (scalar @clauses);
    my $pattern = quotemeta("$database.$schema.$table.");
    $set_clause =~ s/$pattern//g;

    return $set_clause;
}

sub get_row_from_columns($)
{
    my $args = shift;
    $args->{'limit'} = 1;
    my @rows = @{ get_rows_from_columns($args) };
    return $rows[0];
}

sub get_rows_from_columns($)
{
    my $args   = shift;
    my $sub    = (caller(0))[3];

    my $schema    = $args->{'schema'} || 'public';
    my $table     = $args->{'table' } || die "$sub - key table undefined.";

    my $database = $args->{'database'}
        || die "$sub - key database undefined.";

    my $use_writable_handle = $args->{'use_writable_handle'};

    my $where_clause = get_where_clause($args);
    my $order_clause = get_order_clause($args);
    my $limit_clause = get_limit_clause($args);

    my $sql = <<SQL;
SELECT *
FROM   $database.$schema.$table
$where_clause
$order_clause
$limit_clause
SQL

    return sql_returning_rows({
        'sql'                 => $sql,
        'database'            => $database,
        'use_writable_handle' => $use_writable_handle,
    });
}

sub delete_rows_from_columns($)
{
    my $args   = shift;
    my $sub    = (caller(0))[3];

    my $schema    = $args->{'schema'} || 'public';
    my $table     = $args->{'table' } || die "$sub - key table undefined.";

    my $database = $args->{'database'}
        || die "$sub - key database undefined.";

    my $where_clause = get_where_clause($args);

    die "$sub - Cannot be used to delete all rows in a table."
        if (! defined $where_clause || $where_clause eq $EMPTY_STR);

    my $sql = <<SQL;
DELETE
FROM   $database.$schema.$table
$where_clause
SQL

    my $dbh = $writable_handles->{$database}
        || die "$sub - not connected to database '$database'";

    $dbh->do($sql);
    if ($dbh->err) {
        print STDERR "SQL ERROR:" . $dbh->errstr ."\n";
    }
}

sub update_row($)
{
    my $args    = shift;
    my $sub     = (caller(0))[3];

    my $schema  = $args->{'schema' } || 'public';
    my $table   = $args->{'table'  } || die "$sub - key table undefined.";
    my $ids_ref = $args->{'ids_ref'} || die "$sub - key ids_ref undefined.";

    my $database = $args->{'database'}
        || die "$sub - key database undefined.";

    my $where_clause = get_where_clause({
        'database' => $database,
        'schema'   => $schema,
        'table'    => $table,
        'columns'  => $ids_ref,
    });

    my $set_clause = get_set_clause($args);

    my $sql = <<SQL;
UPDATE $database.$schema.$table
$set_clause
$where_clause
RETURNING *
SQL

    my $dbh = $writable_handles->{$database}
        || die "$sub - not connected to database '$database'";

    my $result = $dbh->selectrow_hashref($sql);

    if ($dbh->err) {
        print STDERR "SQL ERROR:" . $dbh->errstr ."\n";
    }

    return $result;
}

sub insert_row($)
{
    my $args        = shift;
    my $sub         = (caller(0))[3];

    my $schema      = $args->{'schema'  } || 'public';

    my $table       = $args->{'table'   }
        || die "$sub - key table undefined.";

    my $columns_ref = $args->{'columns' }
        || die "$sub - key columns undefined.";

    my $database    = $args->{'database'}
        || die "$sub - key database undefined.";

    my @columns = keys %$columns_ref;
    my $columns_string = join(', ', @columns);

    my @values = ();
    foreach my $column (@columns) {
        my $value = $columns_ref->{$column} || $EMPTY_STR;
        my $sub_ref = $special_values->{$value}
            || $special_values->{$UNKNOWN_KEY};

        $value = &$sub_ref($value);
        push(@values, $value);
    }

    my $values_string = join(', ', @values);

    my $sql = <<SQL;
INSERT INTO $database.$schema.$table (
    $columns_string
) VALUES (
    $values_string
) RETURNING *
SQL

    my $dbh = $writable_handles->{$database}
        || die "$sub - not connected to database '$database'";

    my $result = $dbh->selectrow_hashref($sql);
    if ($dbh->err) {
        print STDERR "SQL ERROR:" . $dbh->errstr ."\n";
    }

    return $result;
}

sub lock_tables($)
{
    my $args   = shift;
    my $sub    = (caller(0))[3];

    my $schema = $args->{'schema'} || 'public';

    my $tables = $args->{'lock_tables'}
               || die "$sub - key lock_tables undefined.";

    my $database = $args->{'database'}
        || die "$sub - key database undefined.";

    my $sql = $EMPTY_STR;

    if (! exists $locks->{$database}) {
        my $tables_string = join(', ', @$tables);
        $sql = <<SQL;
BEGIN WORK;
LOCK TABLE $tables_string
SQL
        for my $table (@$tables) {
            $locks->{$database}->{$table} = 1;
        }
    }
    else {
        my @unlocked_tables = ();
        for my $table (@$tables) {
            if (! exists $locks->{$database}->{$table}) {
                $locks->{$database}->{$table} = 1;
                push(@unlocked_tables, $table);
            }
        }

        my $tables_string = join(', ', @unlocked_tables);
        $sql = "LOCK TABLE $tables_string\n";
    }

    if ($sql ne $EMPTY_STR) {
        my $dbh = $writable_handles->{$database}
            || die "$sub - not connected to database '$database'";

        $dbh->do($sql);
        if ($dbh->err) {
            print STDERR "SQL ERROR:" . $dbh->errstr ."\n";
        }
    }
}

sub unlock_tables($)
{
    my $args     = shift;
    my $sub      = (caller(0))[3];

    my $database = $args->{'database'}
        || die "$sub - key database undefined.";

    my $dbh = $writable_handles->{$database}
        || die "$sub - not connected to database '$database'";

    if (exists $locks->{$database}) {
        delete $locks->{$database};
        $dbh->do("COMMIT WORK");
        if ($dbh->err) {
            print STDERR "SQL ERROR:" . $dbh->errstr ."\n";
        }
    }
}

sub find_or_create_row_from_columns($)
{
    my $args = shift;

    return get_row_from_columns($args) || insert_row($args);
}

sub update_or_insert_row_from_columns($)
{
    my $args    = shift;
    my $sub     = (caller(0))[3];

    my $schema  = $args->{'schema' } || 'public';
    my $table   = $args->{'table'  } || die "$sub - key table undefined.";
    my $ids_ref = $args->{'ids_ref'} || die "$sub - key ids_ref undefined.";

    my $database = $args->{'database'}
        || die "$sub - key database undefined.";

    my $row = get_row_from_columns({
        'database' => $database,
        'schema'   => $schema,
        'table'    => $table,
        'columns'  => $ids_ref,
    });

    if (defined $row) {
        $row = update_row($args);
    }
    else {
        $row = insert_row($args);
    }

    return $row;
}

END {
    close_databases($readonly_handles) if (defined $readonly_handles);
    close_databases($writable_handles) if (defined $writable_handles);
    print STDERR "$errstr \n" if ($errstr ne $EMPTY_STR && $?);
}

1;
