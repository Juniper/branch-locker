/*

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

*/

function toggleMode(elem, revealClass, hideClass) {
    revealClass = revealClass || 'edit';
    hideClass = hideClass || 'display';

    var parentNode = $(elem).parents('*.toggle-break:first');
    parentNode.children("*."+revealClass).removeClass("hidden");
    parentNode.children("*."+hideClass).addClass("hidden");
    return false;
}

function toggleDetails(element) {
    found_value = $(element).next();
    if (found_value.hasClass("hidden")) {
        found_value.removeClass("hidden");
    }

    else {
        found_value.addClass("hidden");
    }
}

function rewriteAuditTrailLinks() {
    $('a.audit-trail-link').click(
        function(e) {
            e.preventDefault();
            var audit_div = $(this).parents('*.audit-break:first');
            var uri = this.href + '&no_wrapper=1';
            audit_div.html('<p>Loading ' + uri + ' ...</p>');
            audit_div.load(uri, null, function(responseText, textStatus, xhr) {
                audit_div.html(responseText);
            });

            return false;
        }
    );
}

function rewriteBranchTabLinks() {
    $('a.branch-tab-link').click(
        function(e) {
            e.preventDefault();
            var branch_data_div = $('div.branch-data');
            var uri = this.href + '&no_wrapper=1';
            branch_data_div.html('<p>Loading ' + uri + ' ...</p>');
            branch_data_div.load(uri, null, function(responseText, textStatus, xhr) {
                branch_data_div.html(responseText);
            });

            return false;
        }
    );
}
