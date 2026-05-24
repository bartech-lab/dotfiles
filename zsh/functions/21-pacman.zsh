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

pacman-optimize() {
    echo "Optimizing pacman.conf..."

    # Enable color output
    sudo sed -i 's/^#Color$/Color/' /etc/pacman.conf

    # Enable verbose package lists
    sudo sed -i 's/^#VerbosePkgLists$/VerbosePkgLists/' /etc/pacman.conf

    # Set parallel downloads to 10 (2 Gbps connection)
    if grep -q '^#ParallelDownloads' /etc/pacman.conf; then
        sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    elif grep -q '^ParallelDownloads' /etc/pacman.conf; then
        sudo sed -i 's/^ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    fi

    # Add ILoveCandy if not present
    if ! grep -q '^ILoveCandy' /etc/pacman.conf; then
        sudo sed -i '/^ParallelDownloads/a ILoveCandy' /etc/pacman.conf
    fi

    echo "✓ Pacman config optimized:"
    echo "  • Color output enabled"
    echo "  • Verbose package lists enabled"
    echo "  • Parallel downloads: 10"
    echo "  • ILoveCandy enabled"
}
