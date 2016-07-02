
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

BranchLocker::Controller::ViewGroup - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=cut

package BranchLocker::Controller::ViewGroup;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

my $EMPTY_STR = q{};

=head1 METHODS

=cut

sub group_locks :Global {
    my ($self, $c) = @_;

    my $gui_api_key = $c->config->{'gui_api_key'};
    my $api_key_ref = $c->validate_api_key($gui_api_key);
    my $user        = $c->get_user;
    my $parameters  = $c->req->parameters;

    my $grouped     = $parameters->{'grouped'   };
    my $no_wrapper  = $parameters->{'no_wrapper'};

    my $errors_ref = [];
    if (! defined $grouped) {
        push(@$errors_ref,
            'You must supply a group name to look up locks.');
    }

    my $bread_crumbs = [
        { 'link' => $c->uri_for('/'), 'name' => 'Home' },
    ];

    $c->stash->{'bread_crumbs'} = $bread_crumbs;
    $c->stash->{'no_wrapper'  } = $no_wrapper;

    if (scalar @$errors_ref) {
        $c->stash->{'errors'    } = $errors_ref;
        $c->stash->{'error'     } = "Could not look up group '$grouped'.";
        $c->stash->{'template'  } = 'error.tt2';
    }
    else {
        my $group_mapping = $c->config->{'group_mapping'} || {};
        my $grouped_ref   = $group_mapping->{$grouped} || [$grouped];
    
        my $locks = Branch::Locker::get_locks({
            'grouped' => $grouped_ref,
            'state'   => 'Active',
        });

        my $domain = $c->config->{'domain'};
        foreach my $lock_ref (@$locks) {
            my $lock_name = $lock_ref->{'name'};
            my $gate_keepers = $lock_ref->{'gate_keepers'};
            my $list_of_emails = $gate_keepers;
            $list_of_emails =~ s/(?:^|[ ,])([^ ,]+)(?:[ ,]|$)/$1\@$domain,/g;
            $list_of_emails =~ s/[ ,]+$//;
            my $uri = "mailto:${list_of_emails}?Subject=$lock_name - PR ????  (please fill in)";
            $lock_ref->{'email_gate_keepers'} = $uri;
        }

        $c->stash->{'label'   } = $grouped;
        $c->stash->{'locks'   } = $locks;
        $c->stash->{'template'} = 'view-group-locks.tt2';
    }
}

__PACKAGE__->meta->make_immutable;

1;
