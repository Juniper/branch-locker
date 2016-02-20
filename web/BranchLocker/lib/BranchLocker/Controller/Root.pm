=encoding utf-8

=head1 NAME

BranchLocker::Controller::Root - Root Controller for BranchLocker

=head1 DESCRIPTION

A web app that controls branch based development write access.

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

package BranchLocker::Controller::Root;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller' }

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

=head1 METHODS

=cut

=head2 index

The root page (/)

=cut

sub index :Path :Args(0) {
    my ($self, $c) = @_;

    #$c->response->body( $c->welcome_message );
    my $gui_api_key = $c->config->{'gui_api_key'};
    my $api_key_ref = $c->validate_api_key($gui_api_key);
    my $user        = $c->get_user();
    my $tables      = [];

    my $editable_locks = Branch::Locker::get_locks({
        'gate_keeper' => $user,
        'state'       => 'Active',
    });

    if (scalar @$editable_locks) {
        my @sorted_locks = sort { $a->{'name'} cmp $b->{'name'} } @$editable_locks;
        push (@$tables, {
            'label' => "Locks Editable by: '$user'",
            'locks' => \@sorted_locks,
        });
    }

    my $locks_ref = Branch::Locker::get_locks({
        'state' => 'Active',
    });

    my $grouped_ref = {};
    my @locks = sort { $a->{'name'} cmp $b->{'name'} } @$locks_ref;

    my @release_types = (
        '',
        'Production',
        'Integration',
        'Service',
        'Development',
    );

    my $release_mapping = {
        'Production'  => 'Production',
        'Feature'     => 'Production',
        'Release'     => 'Production',
        'Service'     => 'Service',
        'Exception'   => 'Service',
        'Development' => 'Development',
        'Integration' => 'Integration',
    };

    foreach my $lock_ref (@locks) {
        my $group_name = $release_mapping->{ $lock_ref->{'grouped'} } || q{};
        my $array_ref  = $grouped_ref->{$group_name};
        if (! defined $array_ref) {
            $array_ref = [];
            $grouped_ref->{$group_name} = $array_ref;
        }

        push(@$array_ref, $lock_ref)
            if ($lock_ref->{'name'} ne 'SVN_ADMIN_BRANCH');
    }

    foreach my $group_name (@release_types) {
        my $push_tables = Branch::Locker::is_user_an_admin($user);
        my $grouped_locks = $grouped_ref->{$group_name} || [];
        $push_tables = 1
            if (defined $group_name && $group_name ne q{});

        push (@$tables, {
            'label' => $group_name,
            'locks' => $grouped_locks,
        }) if ($push_tables && scalar @$grouped_locks);
    }

    # Add email link
    foreach my $table_ref (@$tables) {
        my $table_locks = $table_ref->{'locks'};
        foreach my $lock_ref (@$table_locks) {
            my $lock_name = $lock_ref->{'name'};
            my $gate_keepers = $lock_ref->{'gate_keepers'};
            my $list_of_emails = $gate_keepers;
            $list_of_emails =~ s/(?:^|[ ,])([^ ,]+)(?:[ ,]|$)/$1\@example.com,/g;
            $list_of_emails =~ s/[ ,]+$//;
            my $uri = "mailto:${list_of_emails}?Subject=$lock_name - PR ???? (please fill in)";
            $lock_ref->{'email_gate_keepers'} = $uri;
        }
    }

    $c->stash->{'release_types'} = \@release_types;
    $c->stash->{'tables'       } = $tables;
    $c->stash->{'template'     } = 'index.tt2';
}

=head2 default

Standard 404 error page

=cut

sub default :Path {
    my ( $self, $c ) = @_;

    $c->response->body('Page not found');
    $c->response->status(404);
}

=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

__PACKAGE__->meta->make_immutable;

1;
