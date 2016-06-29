
=encoding utf8

=head1 NAME

BranchLocker::Controller::EditLock - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

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

=cut

package BranchLocker::Controller::EditLock;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

my $EMPTY_STR = q{};

=head1 METHODS

=cut

sub edit_lock :Global {
    my ($self, $c) = @_;

    my $gui_api_key = $c->config->{'gui_api_key'};
    my $api_key_ref = $c->validate_api_key($gui_api_key);
    my $user        = $c->get_user;
    my $is_readonly = $c->is_readonly;
    my $parameters  = $c->req->parameters;

    if (! exists $parameters->{'id'}) {
        $c->response->redirect($c->uri_for('/'));
        $c->detach;
    }

    if ($c->is_readonly) {
        $c->stash->{'messages'} = 'Branch Locker is now in read only mode.';
        BranchLocker::Controller::Lock::lock(@_);
        $c->detach;
    }

    my $locks_ref = Branch::Locker::get_locks({ 'lock_id' => $parameters->{'id'} });
    my @locks = @$locks_ref;
    my $lock_ref = $locks[0];

    my $enforcements_ref = Branch::Locker::get_enforcements_from_lock($lock_ref);

    my $user_can_edit   = undef;
    my $user_can_enable = undef;

    # User only needs to be able to edit one enforcement to be able to change
    # edit the lock data.
    # User only needs to be able to enable one enforcement to be able to
    # attempt to change the status.
    foreach my $enforcement_ref (@$enforcements_ref) {
        # Can the user edit the enforcement?
        # We don't care about the errors here.
        $user_can_edit = Branch::Locker::can_edit_enforcement_as_user(
            $enforcement_ref,
            $user,
            [],
        ) if (! $user_can_edit);

        # Can the user enable the enforcement?
        # We don't care about the errors here.
        $user_can_enable = Branch::Locker::can_enable_enforcement_as_user(
            $enforcement_ref,
            $user,
            [],
        ) if (! $user_can_enable);
    }

    my $user_is_admin = Branch::Locker::is_user_an_admin($user);

    my $can_edit   = $user_can_edit   ? $EMPTY_STR : 'disabled';
    my $can_enable = $user_can_enable ? $EMPTY_STR : 'disabled';
    my $admin_only = $user_is_admin   ? $EMPTY_STR : 'disabled';

    my $can_submit = $user_can_edit || $user_can_enable
                   ? $EMPTY_STR
                   : 'disabled'
                   ;

    my $id = $parameters->{'id'};
    my $bread_crumbs = [
        { 'link' => $c->uri_for('/lock') . "?id=$id", 'name' => 'Back' },
    ];

    $c->stash->{'bread_crumbs'} = $bread_crumbs;
    $c->stash->{'can_edit'    } = $can_edit;
    $c->stash->{'can_enable'  } = $can_enable;
    $c->stash->{'admin_only'  } = $admin_only;
    $c->stash->{'can_submit'  } = $can_submit;
    $c->stash->{'lock'        } = $lock_ref;
    $c->stash->{'id'          } = $id;
    $c->stash->{'template'    } = 'edit-lock.tt2';
}

__PACKAGE__->meta->make_immutable;

1;
