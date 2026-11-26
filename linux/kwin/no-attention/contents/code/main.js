// Apps (Brave, Telegram, ...) mark a window "needs attention" when they want focus.
// Plasma then flashes the task and keeps the auto-hide panel shown. Clear the flag.
function watch(w) {
    w.demandsAttentionChanged.connect(function () {
        if (w.demandsAttention) w.demandsAttention = false;
    });
    if (w.demandsAttention) w.demandsAttention = false;
}
workspace.windowList().forEach(watch);
workspace.windowAdded.connect(watch);
