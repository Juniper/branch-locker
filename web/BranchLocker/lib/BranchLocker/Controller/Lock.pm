
=encoding utf8

=head1 AUTHOR

Justin Bellomi

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

=head1 NAME

BranchLocker::Controller::Lock - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=cut

package BranchLocker::Controller::Lock;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 METHODS

=cut

sub lock :Global {
    my ($self, $c) = @_;

    my $gui_api_key = $c->config->{'gui_api_key'};
    my $api_key_ref = $c->validate_api_key($gui_api_key);
    my $user        = $c->get_user;
    my $is_readonly = $c->is_readonly;

    my $lock_id = $c->req->parameters->{'id'    };
    my $branch  = $c->req->parameters->{'branch'};

    my $criteria_ref = {};
    if (defined $lock_id) {
        $criteria_ref->{'lock_id'} = $lock_id;
    }

    elsif (defined $branch) {
        $criteria_ref->{'branch'} = $branch;
    }

    else {
        $c->response->redirect($c->uri_for('/'));
        $c->detach;
    }
 
    my $locks_ref = Branch::Locker::get_locks($criteria_ref);

    my @locks = @$locks_ref;
    my $lock = $locks[0];

    my $lock_locations_ref = Branch::Locker::get_locations_from_locks($lock);
    my $locations_ref = [];
    my $locations_hash_ref = {};

    foreach my $location_ref (@$lock_locations_ref) {
        my $repository = $location_ref->{'repository'};
        my $array_ref = $locations_hash_ref->{$repository};
        if (! defined $array_ref) {
            $array_ref = [];
            $locations_hash_ref->{$repository} = $array_ref;
        }

        push(@$array_ref, $location_ref->{'path'});
    }

    foreach my $repository (sort keys %$locations_hash_ref) {
        push(@$locations_ref, {
            'repository' => $repository,
            'paths'      => $locations_hash_ref->{$repository},
        });
    }

    $lock->{'locations'} = $locations_ref;

    my $lock_enforcements
        = Branch::Locker::get_enforcements_from_lock($lock);

    foreach my $enforcement (@$lock_enforcements) {
        if ($enforcement->{'is_enabled'}) {
            $enforcement->{'is_enabled_string'} = 'Yes';
            $enforcement->{'toggle_string'    } = 'Disable';
            $enforcement->{'enabled_class'    } = 'enabled';
        }
        else {
            $enforcement->{'is_enabled_string'} = 'No';
            $enforcement->{'toggle_string'    } = 'Enable';
            $enforcement->{'enabled_class'    } = 'disabled';
        }

        # Can the user edit the enforcement?
        # We don't care about the errors here.
        my $can_edit_enforcement
            = Branch::Locker::can_edit_enforcement_as_user(
                $enforcement,
                $user,
                [],
            );

        $enforcement->{'can_edit'} = 1 if (
            ! $is_readonly && $can_edit_enforcement
        );

        # Can the user enable the enforcement?
        # We don't care about the errors here.
        my $can_enable_enforcement
            = Branch::Locker::can_enable_enforcement_as_user(
                $enforcement,
                $user,
                [],
            );

        $enforcement->{'can_enable'} = 1 if (
            ! $is_readonly && $can_enable_enforcement
        );

        $lock->{'can_edit'} = 1 if ($enforcement->{'can_edit'});
    }

    $lock->{'enforcements'} = $lock_enforcements;

    # Setup request to change gatekeepers email.
    if (! Branch::Locker::is_user_an_admin($user)) {
        my $gate_keeper_admin_email = $c->config->{'gate_keeper_admin_email'};
        my $subject = "Gatekeeper change request for $lock->{'name'}";
        my $body = 'WARNING:%20THIS%20SHOULD%20NOT%20BE%20USED%20TO%20REQUEST%20COMMIT%20ACCESS.%0D%0AEmail%20Subject%20line%20defaults%20to%20Branch%20name.%0D%0APlease%20add%20PR%20number(s)%20being%20requested%20after%20branch%20name.%0D%0A';

        my $email_link
            = 'mailto:'    . $gate_keeper_admin_email
            . '?subject='  . $subject
            . '&body=' . $body
            ;

        $lock->{'request_change'} = $email_link;
    }

    my $bread_crumbs = [
        { 'link' => $c->uri_for('/'), 'name' => 'Home' },
    ];

    my $link_to_audit_trail = $c->uri_for('/audittrail')
        . "?object=lock&id=$lock_id";

    $c->stash->{'lock'               } = $lock;
    $c->stash->{'bread_crumbs'       } = $bread_crumbs;
    $c->stash->{'link_to_audit_trail'} = $link_to_audit_trail;
    $c->stash->{'template'           } = 'lock.tt2';
}

__PACKAGE__->meta->make_immutable;

1;
