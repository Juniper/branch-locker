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
