(function () {
    const target = "/collection/tracks";

    function redirectHome() {
        if (!Spicetify?.Platform?.History) return;

        const path = Spicetify.Platform.History.location.pathname;

        if (path === "/" || path === "/home") {
            Spicetify.Platform.History.replace(target);
        }
    }

    function init() {
        if (!Spicetify?.Platform?.History) {
            setTimeout(init, 300);
            return;
        }

        redirectHome();
        Spicetify.Platform.History.listen(redirectHome);
    }

    init();
})();
