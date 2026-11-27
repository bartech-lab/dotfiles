// Liked Songs on startup + no home redirect
(function() {
    var done = false;
    var LIKED = "/collection/tracks";

    function goLiked() {
        if (done) return;
        try {
            if (typeof Spicetify !== "undefined" && Spicetify.Platform) {
                var hist = Spicetify.Platform.History;
                if (hist && hist.push && hist.replace) {
                    hist.push(LIKED);
                    hist.replace(LIKED);
                    done = true;
                }
            }
        } catch(e) {
            // fallback: try direct history API
            try {
                history.replaceState(null, "", LIKED);
                history.pushState(null, "", LIKED);
                done = true;
            } catch(e2) {}
        }
    }

    // multiple retries
    [300, 600, 1000, 2000, 4000].forEach(function(ms) {
        setTimeout(goLiked, ms);
    });

    // intercept home navigation
    var origPush = history.pushState;
    history.pushState = function() {
        var url = arguments[2];
        if (typeof url === "string" && url.indexOf("/home") !== -1 && !done) {
            goLiked();
            return;
        }
        return origPush.apply(this, arguments);
    };

    var origReplace = history.replaceState;
    history.replaceState = function() {
        var url = arguments[2];
        if (typeof url === "string" && url.indexOf("/home") !== -1 && !done) {
            goLiked();
            return;
        }
        return origReplace.apply(this, arguments);
    };
})();
