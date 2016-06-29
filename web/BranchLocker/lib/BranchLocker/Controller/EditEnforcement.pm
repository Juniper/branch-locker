
=encoding utf8

=head1 NAME

BranchLocker::Controller::EditEnforcement - Catalyst Controller

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

package BranchLocker::Controller::EditEnforcement;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 METHODS

=cut

=head2 index

=cut

my $EMPTY_STR = q{};

sub edit_enforcement :Global {
    my ($self, $c) = @_;

    my $gui_api_key = $c->config->{'gui_api_key'};
    my $api_key_ref = $c->validate_api_key($gui_api_key);
    my $user        = $c->get_user();
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

    my $enforcements_ref = Branch::Locker::get_enforcements($parameters);

    my @enforcements = @$enforcements_ref;
    my $enforcement = $enforcements[0];

    if ($enforcement->{'is_enabled'}) {
        $enforcement->{'is_enabled_value' } = 1;
        $enforcement->{'is_enabled'       } = 'checked';
        $enforcement->{'enabled_class'    } = 'enabled';
    }
    else {
        $enforcement->{'is_enabled_value' } = 0;
        $enforcement->{'is_enabled'       } = '';
        $enforcement->{'enabled_class'    } = 'disabled';
    }

    # Can the user edit the enforcement?
    # We don't care about the errors here.
    my $user_can_edit = Branch::Locker::can_edit_enforcement_as_user(
            $enforcement,
            $user,
            [],
        );

    # Can the user enable the enforcement?
    # We don't care about the errors here.
    my $user_can_enable = Branch::Locker::can_enable_enforcement_as_user(
            $enforcement,
            $user,
            [],
        );

    my $user_is_admin = Branch::Locker::is_user_an_admin($user);

    my $can_edit   = $user_can_edit   ? $EMPTY_STR : 'disabled';
    my $can_enable = $user_can_enable ? $EMPTY_STR : 'disabled';
    my $admin_only = $user_is_admin   ? $EMPTY_STR : 'disabled';
    my $can_submit = $user_can_edit || $user_can_enable
                   ? $EMPTY_STR
                   : 'disabled'
                   ;

    my $from_lock_id = $parameters->{'from_lock_id'} || $EMPTY_STR;
    my $bread_crumbs = [
        {
            'link' => $c->uri_for('/lock') . "?id=$from_lock_id",
            'name' => 'Back',
        },
    ];

    $c->stash->{'bread_crumbs'} = $bread_crumbs;
    $c->stash->{'can_edit'    } = $can_edit;
    $c->stash->{'can_enable'  } = $can_enable;
    $c->stash->{'admin_only'  } = $admin_only;
    $c->stash->{'can_submit'  } = $can_submit;
    $c->stash->{'from_lock_id'} = $from_lock_id;
    $c->stash->{'enforcement' } = $enforcement;
    $c->stash->{'template'    } = 'edit-enforcement.tt2';
}

sub submit_edit_enforcement :Global {
    my ($self, $c) = @_;

    my $gui_api_key = $c->config->{'gui_api_key'};
    my $api_key_ref = $c->validate_api_key($gui_api_key);
    my $user        = $c->get_user();
    my $parameters  = $c->req->parameters;

    if (! exists $parameters->{'id'}) {
        $c->response->redirect($c->uri_for('/'));
        $c->detach;
    }

    if ($c->is_readonly) {
        $c->stash->{'errors'} = <<ERROR;
Branch Locker was put into read only mode, your edits have been discarded.
ERROR
        BranchLocker::Controller::Lock::lock(@_);
        $c->detach;
    }

    my $id                       = $parameters->{'id'                      };
    my $from_lock_id             = $parameters->{'from_lock_id'            };

    my $old_name                 = $parameters->{'old_name'                }
                                 || $EMPTY_STR;

    my $new_name                 = $parameters->{'new_name'                }
                                 || $EMPTY_STR;

    my $old_is_enabled           = $parameters->{'old_is_enabled'          }
                                 || $EMPTY_STR;
    my $new_is_enabled           = $parameters->{'new_is_enabled'          }
                                 || $EMPTY_STR;

    my $old_users_who_can_enable = $parameters->{'old_users_who_can_enable'}
                                 || $EMPTY_STR;
    my $new_users_who_can_enable = $parameters->{'new_users_who_can_enable'}
                                 || $EMPTY_STR;

    my $old_users_who_can_edit   = $parameters->{'old_users_who_can_edit'  }
                                 || $EMPTY_STR;
    my $new_users_who_can_edit   = $parameters->{'new_users_who_can_edit'  }
                                 || $EMPTY_STR;

    my $old_allowed_users        = $parameters->{'old_allowed_users'       }
                                 || $EMPTY_STR;
    my $new_allowed_users        = $parameters->{'new_allowed_users'       }
                                 || $EMPTY_STR;

    my $old_allowed_prs          = $parameters->{'old_allowed_prs'         }
                                 || $EMPTY_STR;
    my $new_allowed_prs          = $parameters->{'new_allowed_prs'         }
                                 || $EMPTY_STR;

    # Detect Changes.
    my $changes = {};

    $changes->{'name'} = $new_name if ($old_name ne $new_name);

    $changes->{'is_enabled'} = $new_is_enabled
        if ($old_is_enabled ne $new_is_enabled);

    my ($added_users_who_can_enable, $removed_users_who_can_enable)
        = Branch::Locker::get_added_and_removed_values(
            $old_users_who_can_enable, $new_users_who_can_enable
    );

    $changes->{'add-users-who-can-enable'} = $added_users_who_can_enable
        if (scalar @$added_users_who_can_enable);

    $changes->{'remove-users-who-can-enable'} = $removed_users_who_can_enable
        if (scalar @$removed_users_who_can_enable);

    my ($added_users_who_can_edit, $removed_users_who_can_edit)
        = Branch::Locker::get_added_and_removed_values(
            $old_users_who_can_edit, $new_users_who_can_edit
    );

    $changes->{'add-users-who-can-edit'} = $added_users_who_can_edit
        if (scalar @$added_users_who_can_edit);

    $changes->{'remove-users-who-can-edit'} = $removed_users_who_can_edit
        if (scalar @$removed_users_who_can_edit);

    my ($added_allowed_users, $removed_allowed_users)
        = Branch::Locker::get_added_and_removed_values(
            $old_allowed_users, $new_allowed_users
    );

    $changes->{'add-allowed-users'} = $added_allowed_users
        if (scalar @$added_allowed_users);

    $changes->{'remove-allowed-users'} = $removed_allowed_users
        if (scalar @$removed_allowed_users);

    my ($added_allowed_prs, $removed_allowed_prs)
        = Branch::Locker::get_added_and_removed_values(
            $old_allowed_prs, $new_allowed_prs
    );

    $changes->{'add-allowed-prs'} = $added_allowed_prs
        if (scalar @$added_allowed_prs);

    $changes->{'remove-allowed-prs'} = $removed_allowed_prs
        if (scalar @$removed_allowed_prs);

    $changes->{'as-user'} = $user;
    my $enforcements_ref = Branch::Locker::get_enforcements({ 'id' => $id });
    my $audit_transaction = Branch::Locker::edit_enforcements(
        $api_key_ref,
        $enforcements_ref,
        $changes,
    );

    if (exists $audit_transaction->{'errors'}) {
        $c->stash->{'errors'      } = $audit_transaction->{'errors'};
    }
    else {
        $c->stash->{'messages'    } = 'Edit successful.';
    }

    edit_enforcement(@_);
}

sub submit_legacy_edit_lock :Global {
    my ($self, $c) = @_;

    my $gui_api_key = $c->config->{'gui_api_key'};
    my $api_key_ref = $c->validate_api_key($gui_api_key);
    my $user        = $c->get_user();
    my $parameters  = $c->req->parameters;

    if (! exists $parameters->{'id'}
        || ! exists $parameters->{'from_lock_id'}) {
        $c->response->redirect($c->uri_for('/'));
        $c->detach;
    }

    if ($c->is_readonly) {
        $c->stash->{'errors'} = <<ERROR;
Branch Locker was put into read only mode, your edits have been discarded.
ERROR
        BranchLocker::Controller::Lock::lock(@_);
        $c->detach;
    }

    my $id                       = $parameters->{'id'                      };
    my $from_lock_id             = $parameters->{'from_lock_id'            };

    my $old_name                 = $parameters->{'old_name'                }
                                 || $EMPTY_STR;

    my $new_name                 = $parameters->{'new_name'                }
                                 || $EMPTY_STR;

    my $old_is_enabled           = $parameters->{'old_is_enabled'          }
                                 || $EMPTY_STR;
    my $new_is_enabled           = $parameters->{'new_is_enabled'          }
                                 || $EMPTY_STR;

    my $old_users_who_can_enable = $parameters->{'old_users_who_can_enable'}
                                 || $EMPTY_STR;
    my $new_users_who_can_enable = $parameters->{'new_users_who_can_enable'}
                                 || $EMPTY_STR;

    my $old_users_who_can_edit   = $parameters->{'old_users_who_can_edit'  };
    my $new_users_who_can_edit   = $parameters->{'new_users_who_can_edit'  };

    my $old_allowed_users        = $parameters->{'old_allowed_users'       };
    my $new_allowed_users        = $parameters->{'new_allowed_users'       };

    my $old_allowed_prs          = $parameters->{'old_allowed_prs'         };
    my $new_allowed_prs          = $parameters->{'new_allowed_prs'         };

    my $old_message              = $parameters->{'old_message'             }
                                 || $EMPTY_STR;
    my $new_message              = $parameters->{'new_message'             }
                                 || $EMPTY_STR;

    my $old_status               = $parameters->{'old_status'              }
                                 || $EMPTY_STR;
    my $new_status               = $parameters->{'new_status'              }
                                 || $EMPTY_STR;

    my $old_state                = $parameters->{'old_state'               }
                                 || $EMPTY_STR;
    my $new_state                = $parameters->{'new_state'               }
                                 || $EMPTY_STR;

    # Detect Changes.
    my $changes = {};

    if (defined $old_users_who_can_edit && defined $new_users_who_can_edit) {
        my ($added_users_who_can_edit, $removed_users_who_can_edit)
            = Branch::Locker::get_added_and_removed_values(
                $old_users_who_can_edit, $new_users_who_can_edit
        );

        $changes->{'add-gate-keepers'} = $added_users_who_can_edit
            if (scalar @$added_users_who_can_edit);

        $changes->{'remove-gate-keepers'} = $removed_users_who_can_edit
            if (scalar @$removed_users_who_can_edit);
    }

    if (defined $old_allowed_users && defined $new_allowed_users) {
        my ($added_allowed_users, $removed_allowed_users)
            = Branch::Locker::get_added_and_removed_values(
                $old_allowed_users, $new_allowed_users
        );

        $changes->{'add-users'} = $added_allowed_users
            if (scalar @$added_allowed_users);

        $changes->{'remove-users'} = $removed_allowed_users
            if (scalar @$removed_allowed_users);
    }

    if (defined $old_allowed_prs && defined $new_allowed_prs) {
        my ($added_allowed_prs, $removed_allowed_prs)
            = Branch::Locker::get_added_and_removed_values(
                $old_allowed_prs, $new_allowed_prs
        );

        $changes->{'add-prs'} = $added_allowed_prs
            if (scalar @$added_allowed_prs);

        $changes->{'remove-prs'} = $removed_allowed_prs
            if (scalar @$removed_allowed_prs);
    }

    if ($old_message ne $new_message) {
        $new_message =~ s/\r//g;
        $changes->{'replace-message'} = $new_message;
    }

    $changes->{'set-status'     } = $new_status  if ($old_status  ne $new_status );
    $changes->{'set-state'      } = $new_state   if ($old_state   ne $new_state  );

    if (scalar keys %$changes) {
        $changes->{'as-user'} = $user;

        my $locks_ref = Branch::Locker::get_locks({ 'lock_id' => $from_lock_id });
        my $audit_transaction = Branch::Locker::edit_locks(
            $api_key_ref,
            $locks_ref,
            $changes,
        );

        if (exists $audit_transaction->{'errors'}) {
            $c->stash->{'errors'} = $audit_transaction->{'errors'};
        }
        else {
            $c->stash->{'messages'} = 'Edit successful.';
        }
    }
    else {
        $c->stash->{'messages'} = 'No changes submitted.';
    }

    if ($parameters->{'from_edit_enforcement'}) {
        edit_enforcement(@_);
    }
    elsif ($parameters->{'from_edit_lock'}) {
        BranchLocker::Controller::EditLock::edit_lock(@_);
    }
    else {
        BranchLocker::Controller::Lock::lock(@_);
    }
}

__PACKAGE__->meta->make_immutable;

1;
