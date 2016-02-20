
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

BranchLocker::Controller::Hello - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=cut

package BranchLocker::Controller::Hello;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 METHODS

=cut

=head2 index

=cut

sub hello :Global {
    my ($self, $c, @args) = @_;

    my $word = $args[0] || $c->config->{'word'};
    $c->stash->{'template'} = 'hello.tt2';
    $c->stash->{'word'    } = $word;
}

__PACKAGE__->meta->make_immutable;

1;
