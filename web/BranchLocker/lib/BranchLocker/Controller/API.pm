
=encoding utf8

=head1 AUTHOR

Justin Bellomi

=head1 NAME

BranchLocker::Controller::API - REST API.

=head1 DESCRIPTION

The REST API for Branch Locker.

=head1 LICENSE

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

=cut

package BranchLocker::Controller::API;
use Moose;
use namespace::autoclean;

use Branch::Locker;

BEGIN { extends 'Catalyst::Controller::REST'; }

=head1 METHODS

=cut

__PACKAGE__->config(
    'default'   => 'application/json',
    'map'       => {
        'application/json' => 'JSON',
    },
);

sub exit_readonly :Private {
    my ($self, $c) = @_;

    $self->status_forbidden($c,
        'message' => 'Branch Locker is in read only mode.',
    );

    $c->detach;
}

sub begin :ActionClass('Deserialize') {
    my ($self, $c) = @_;

    # Validate API key.
    my $api_key     = $c->req->header('X-API-Key');
    my $api_key_ref = $c->validate_api_key($api_key);
    if (! defined $api_key_ref) {
        # Unauthorized redirect to help.
        my $status = 403;
        my $error_string = "You are not authorized to use the REST API.";

        my $errors = $c->stash->{'errors'};
        if (exists $c->stash->{'errors'} && scalar @$errors) {
            $status = 500;
            $error_string = join ("\n", @$errors);
        }

        $c->res->status($status);
        $c->res->body($error_string);
        $c->detach;
    }

    $c->stash->{'api_key_ref'} = $api_key_ref;
}

sub check_for_errors :Private {
    my ($data_ref, $self, $c) = @_;

    if (exists $data_ref->{'errors'}) {
        my $errors_ref = $data_ref->{'errors'};
        if (scalar @$errors_ref) {
            my $errors_string = join("\n", @$errors_ref);
            my $error_code = $data_ref->{'http_error_code'} || 400;
            # Respond with error messages.
            $c->res->status($error_code);
            $c->res->body(<<ERRORS);
Encountered Errors:
$errors_string
ERRORS
            $c->detach;
        }
    }
}

sub api :Global {}

sub api_help :Local :Path(0) {
    my ($self, $c) = @_;

    $self->status_ok($c, entity => {
        'API Help' => 'There is no help defined.',
    });

    $c->detach;
}

sub legacy_lock :Local :ActionClass('REST') {}

sub legacy_lock_GET {
    my ($self, $c) = @_;

    my $criteria_ref = $c->req->parameters;
    my $locks_ref = Branch::Locker::get_locks($criteria_ref);

    $self->status_ok($c, entity => $locks_ref);
}

sub legacy_lock_PUT {
    my ($self, $c) = @_;

    my $criteria_ref          = $c->req->data->{'criteria'         };
    my $data_manipulation_ref = $c->req->data->{'data_manipulation'};

    my $user = $data_manipulation_ref->{'as-user'};
    exit_readonly($self, $c) if ($c->is_readonly($user));

    my $auto_create_lock      = $data_manipulation_ref->{'auto-create-lock'};
    my $locks_ref = Branch::Locker::get_locks($criteria_ref);

    # Create a lock if no locks were found.
    if (! scalar @$locks_ref) {
        my $branchname = $criteria_ref->{'branch'    };
        my $repository = $criteria_ref->{'repository'} || 'example-repository';
        if ($auto_create_lock
            && defined $branchname
            && $branchname ne q{}) {
            my $data_ref = {
                'name'      => $branchname,
                'message'   => 'Auto Created Lock - No Message Supplied.',
                'is_active' => 1,
                'is_open'   => 0,
            };

            my $value = undef;

            $value = $data_manipulation_ref->{'as-user'         };
            $data_ref->{'as-user'      } = $value if (defined $value);

            $value = $data_manipulation_ref->{'add-users'       };
            $data_ref->{'allowed-users'} = $value if (defined $value);

            $value = $data_manipulation_ref->{'add-prs'         };
            $data_ref->{'allowed-prs'  } = $value if (defined $value);

            $value = $data_manipulation_ref->{'add-gate-keepers'};
            $data_ref->{'gate-keepers' } = $value if (defined $value);

            $value = $data_manipulation_ref->{'replace-message' };
            $data_ref->{'message'      } = $value if (defined $value);

            my $audit_transaction_ref = Branch::Locker::create_lock(
                $c->stash->{'api_key_ref'},
                $data_ref,
            );
            check_for_errors($audit_transaction_ref, $self, $c);

            my $lock_ref = $audit_transaction_ref->{'result'};

            my $path = $branchname eq 'HEAD' ? '/trunk/'
                     :                         "/branches/$branchname/"
                     ;

            my $location_ref = Branch::Locker::find_or_create_location_from_path_and_repository(
                $path,
                $repository
            );

            Branch::Locker::link_location_to_lock($location_ref, $lock_ref);

            $self->status_ok($c, entity => $lock_ref);
        }
        elsif (! $auto_create_lock) {
            my $error_message = <<ERROR;
No locks found for editing.

Set the 'auto-create-lock' sub key under the data_manipulation key
to auto-create a lock.
ERROR
            my $error = {
                'errors'          => [$error_message],
                'http_error_code' => 400,
            };
            check_for_errors($error, $self, $c);
        }
        else {
            my $error_message = <<ERROR;
To auto-create a lock the 'branch' sub key must be defined under the
'criteria' key and it must not be blank.
ERROR
            my $error = {
                'errors'          => [$error_message],
                'http_error_code' => 400,
            };
            check_for_errors($error, $self, $c);
        }
    }
    else {
        my $result = Branch::Locker::edit_locks(
            $c->stash->{'api_key_ref'},
            $locks_ref,
            $data_manipulation_ref
        );
        check_for_errors($result, $self, $c);

        $self->status_ok($c, entity => $result);
    }
}

sub location :Local :ActionClass('REST') {}

sub location_GET {
    my ($self, $c) = @_;

    my $locations
        = Branch::Locker::get_locations_from_locks($c->req->parameters->{'id'})
        || [];

    $self->status_ok($c, entity => $locations);
}

sub echo :Local :ActionClass('REST') {}

sub echo_GET {
    my ($self, $c) = @_;

    $self->status_ok($c, entity => $c->req->parameters);
}

sub echo_POST {
    my ($self, $c) = @_;

    exit_readonly($self, $c) if ($c->is_readonly);

    $self->status_ok($c, entity => $c->req->data);
}

sub echo_PUT {
    my ($self, $c) = @_;

    exit_readonly($self, $c) if ($c->is_readonly);
    
    $self->status_ok($c, entity => $c->req->data);
}

__PACKAGE__->meta->make_immutable;

1;
