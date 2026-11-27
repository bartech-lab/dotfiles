#!/usr/bin/env bash
# Spicetify settings used on archpc and privmac, then apply them to Spotify.
#   bash ~/dotfiles/scripts/spicetify-setup.sh
# Needs: spicetify-cli, the Marketplace custom app in ~/.config/spicetify/CustomApps/marketplace
# (installed with Spicetify's Marketplace installer; it also provides the "marketplace" theme),
# and Spotify quit or restartable. Extensions come from config/spicetify/Extensions via install.sh.
set -euo pipefail
command -v spicetify >/dev/null || { echo "spicetify missing: install spicetify-cli" >&2; exit 1; }
spicetify config >/dev/null  # creates config-xpui.ini with this machine's Spotify paths on first run
spicetify config \
    current_theme marketplace color_scheme Deep \
    inject_theme_js 1 inject_css 1 replace_colors 1 overwrite_assets 0 \
    check_spicetify_update 1 always_enable_devtools 0 \
    disable_sentry 1 disable_ui_logging 1 remove_rtl_rule 1 expose_apis 1 \
    extensions noHomeRedirect.js custom_apps marketplace \
    sidebar_config 0 home_config 1 experimental_features 1
# `backup apply` refuses (and still exits 0) when a backup exists, so back up only the first time.
# Spicetify 2.x keeps it in $XDG_STATE_HOME/spicetify/Backup.
backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/spicetify/Backup"
if [ -n "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
    spicetify apply
else
    spicetify backup apply
fi
