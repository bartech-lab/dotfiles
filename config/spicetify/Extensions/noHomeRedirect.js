(function () {
    const target = "/collection/tracks";

    function redirect() {
        if (Spicetify?.Platform?.History?.location?.pathname === "/") {
            Spicetify.Platform.History.replace(target);
        }
    }

    function init() {
        if (!Spicetify?.Platform?.History) {
            setTimeout(init, 300);
            return;
        }

        redirect();
        Spicetify.Platform.History.listen(redirect);
    }

    init();
})();
