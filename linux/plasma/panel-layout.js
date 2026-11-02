var test = typeof KDE_PANEL_TEST !== "undefined";
if (!test) {
    panels().forEach(function (p) { p.remove(); });
}

var panel = new Panel("org.kde.panel");
panel.location = test ? "top" : "bottom";
panel.height = 56;
panel.hiding = "dodgewindows";
panel.alignment = "center";
panel.lengthMode = "fill";
panel.floating = false;
panel.opacity = "adaptive";

function add(plugin, group, values) {
    var w = panel.addWidget(plugin);
    if (group) {
        w.currentConfigGroup = group;
        for (var k in values) w.writeConfig(k, values[k]);
    }
    return w;
}

add("org.kde.plasma.kickoff");
add("org.kde.plasma.panelspacer", ["General"], { expanding: true });
add("org.kde.plasma.icontasks", ["General"], { launchers: [
    "preferred://filemanager",
    "applications:eu.betterbird.Betterbird.desktop",
    "applications:electron-mail.desktop",
    "applications:tradingview.desktop",
    "applications:standard-notes.desktop",
    "applications:com.rtosta.zapzap.desktop",
    "applications:io.github.tdesktop_x64.TDesktop.desktop",
    "applications:discord.desktop",
    "preferred://browser",
    "applications:spotify.desktop",
    "applications:org.kde.plasma-systemmonitor.desktop",
    "applications:io.missioncenter.MissionCenter.desktop",
    "applications:org.wezfurlong.wezterm.desktop",
    "applications:code-oss.desktop"
] });
add("org.kde.plasma.panelspacer", ["General"], { expanding: true });
add("org.kde.plasma.marginsseparator");
add("org.kde.plasma.systemtray", ["General"], {
    disabledStatusNotifiers: ["firewall-applet"],
    extraItems: [
        "org.kde.plasma.clipboard", "org.kde.plasma.keyboardindicator", "org.kde.plasma.keyboardlayout",
        "org.kde.plasma.battery", "org.kde.plasma.bluetooth", "org.kde.kscreen", "org.kde.plasma.devicenotifier",
        "org.kde.plasma.networkmanagement", "org.kde.plasma.volume", "org.kde.plasma.cameraindicator",
        "org.kde.plasma.manage-inputmethod", "org.kde.plasma.mediacontroller", "org.kde.plasma.brightness",
        "org.kde.plasma.notifications", "org.kde.plasma.printmanager", "org.kde.plasma.weather",
        "org.kde.plasma.dwellclicker"
    ]
});
add("org.kde.netspeedWidget", ["General"], { swapDownUp: true });
add("org.kde.plasma.digitalclock", ["Appearance"], { fontWeight: 400 });
add("org.kde.plasma.showdesktop");
