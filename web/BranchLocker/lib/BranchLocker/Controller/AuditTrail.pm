
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

BranchLocker::Controller::AuditTrail - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=cut

package BranchLocker::Controller::AuditTrail;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 METHODS

=cut

sub audittrail :Global {
    my ($self, $c) = @_;

    my $gui_api_key = $c->config->{'gui_api_key'};
    my $api_key_ref = $c->validate_api_key($gui_api_key);
    my $user        = $c->get_user;

    my $object_id   = $c->req->parameters->{'id'       };
    my $object_type = $c->req->parameters->{'object'   };
    my $no_wrapper  = $c->req->parameters->{'nowrapper'};

    my $errors_ref = [];
    if (! defined $object_id) {
        push(@$errors_ref,
            'You must supply an id to look up the audit trail.');
    }

    if (! defined $object_type) {
        push(@$errors_ref,
            'You must supply an object type to look up the audit trail.');
    }

    if (scalar @$errors_ref) {
        $c->stash->{'nowrapper'} = $no_wrapper;
        $c->stash->{'errors'   } = $errors_ref;
        $c->stash->{'error'    } = 'Could not look up audit trail.';
        $c->stash->{'template' } = 'error.tt2';
    }
    else {
        my $audit_transactions
            = Branch::Locker::get_audit_trail($object_type, $object_id);

        my @audit_trail
            = map { $audit_transactions->{$_} }
            sort { $b <=> $a } keys %$audit_transactions;

        $c->stash->{'nowrapper'  } = $no_wrapper;
        $c->stash->{'audit_trail'} = \@audit_trail;
        $c->stash->{'object_type'} = $object_type;
        $c->stash->{'template'   } = 'view-audit-trail.tt2';
    }
}

__PACKAGE__->meta->make_immutable;

1;
