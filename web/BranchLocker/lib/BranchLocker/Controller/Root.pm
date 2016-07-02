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

    my $group_order = $c->config->{'group_order'} || [];

    $c->stash->{'groups'  } = $group_order;
    $c->stash->{'template'} = 'index.tt2';
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
