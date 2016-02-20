
=encoding utf8

=head1 NAME

BranchLocker - Catalyst based application

=head1 SYNOPSIS

    script/branchlocker_server.pl

=head1 DESCRIPTION

Web app to help manage branch based write access.

=head1 SEE ALSO

L<BranchLocker::Controller::Root>, L<Catalyst>

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

package BranchLocker;
use Moose;
use namespace::autoclean;

use Catalyst::Runtime 5.80;

# Set flags and add plugins for the application.
#
# Note that ORDERING IS IMPORTANT here as plugins are initialized in order,
# therefore you almost certainly want to keep ConfigLoader at the head of the
# list if you're using it.
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a Config::General file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
    -Debug
    Authentication
    ConfigLoader
    Static::Simple
/;

extends 'Catalyst';

our $VERSION = '0.01';

# Configure the application.
#
# Note that settings in branchlocker.conf (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with an external configuration file acting as an override for
# local deployment.

__PACKAGE__->config(
    name => 'BranchLocker',
    # Disable deprecated behavior needed by old applications
    disable_component_resolution_regex_fallback => 1,
    enable_catalyst_header => 1, # Send X-Catalyst header
);

# Start the application
__PACKAGE__->setup();

sub get_user :Private {
    my ($c) = @_;
    my $debug_user  = $c->req->env->{'DEBUG_USER' } || $ENV{'DEBUG_USER' };
    my $remote_user = $c->req->env->{'REMOTE_USER'} || $ENV{'REMOTE_USER'};

    my $user = $debug_user || $remote_user || getpwuid($<);

    return lc $user;
}

sub is_readonly :Private {
    my ($c, $user) = @_;

    $user = $c->get_user if (! defined $user);

    my $config              = $c->config;
    my $readonly            = $config->{'readonly'           };
    my $readonly_exceptions = $config->{'readonly_exceptions'};
    my %read_only_users = map { $_ => 1 } @$readonly_exceptions;

    return ($readonly && ! exists $read_only_users{$user});
}

sub validate_api_key :Private {
    my ($c, $api_key) = @_;

    my $bl_config = $c->config->{'Branch::Locker'};
    $Branch::Locker::readwrite_user   = $bl_config->{'readwrite_user'  };
    $Branch::Locker::readwrite_pass   = $bl_config->{'readwrite_pass'  };
    $Branch::Locker::readwrite_host   = $bl_config->{'readwrite_host'  };

    $Branch::Locker::readonly_user    = $bl_config->{'readonly_user'   };
    $Branch::Locker::readonly_pass    = $bl_config->{'readonly_pass'   };
    my $databases                     = $bl_config->{'databases'       };
    $Branch::Locker::database_servers = $bl_config->{'database_servers'};

    my $api_key_ref = undef;

    eval {
        $api_key_ref = Branch::Locker::init({
            'writable'  => 1,
            'databases' => $databases,
            'api_key'   => $api_key,
        });
    };

    if ($@) {
        my @errors = ('Errors initializing database connections.', $@);
        $c->stash->{'errors'} = \@errors;
    }

    return $api_key_ref;
}

1;
