# Pacman/Yay helpers for Arch Linux
[[ "$DOTFILES_OS" != linux ]] && return 0

pacup() {
    echo "🔄 Updating system packages..."
    sudo pacman -Syu
    if command -v yay &>/dev/null; then
        echo ""
        echo "🔄 Updating AUR packages..."
        yay -Sua --noconfirm
    fi
    echo ""
    echo "✓ System updated"
}

pacclean() {
    echo "🧹 Cleaning package cache..."
    if command -v paccache &>/dev/null; then
        sudo paccache -rk2
    else
        echo "Install pacman-contrib for paccache: sudo pacman -S pacman-contrib"
    fi
    echo "✓ Cache cleaned"
}

pacorphans() {
    echo "🔍 Checking for orphaned packages..."
    local orphans
    orphans=$(pacman -Qdtq 2>/dev/null)
    if [[ -z "$orphans" ]]; then
        echo "✓ No orphaned packages found"
    else
        echo ""
        echo "Orphaned packages:"
        echo "$orphans"
        echo ""
        echo "Remove with: sudo pacman -Rns \$(pacman -Qdtq)"
    fi
}
