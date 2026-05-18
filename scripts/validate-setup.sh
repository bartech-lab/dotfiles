#!/usr/bin/env zsh

# Dotfiles Validation Script
# Run this after install.sh to verify everything is working correctly

# Don't use set -e as we want to continue on failures

echo "🔍 Dotfiles Validation"
echo "======================"
echo ""

PASS=0
FAIL=0
WARN=0

pass() {
    echo "  ✅ $1"
    ((PASS++))
}

fail() {
    echo "  ❌ $1"
    ((FAIL++))
}

warn() {
    echo "  ⚠️  $1"
    ((WARN++))
}

# ============================================================================
# System Requirements
# ============================================================================

echo "System Requirements:"

# Platform detection
case "$(uname -s)" in
    Darwin) DOTFILES_OS=macos ;;
    Linux)  DOTFILES_OS=linux ;;
    *)      DOTFILES_OS=unknown ;;
esac

if [[ "$DOTFILES_OS" == macos ]]; then
    # macOS version
    macos_version=$(sw_vers -productVersion 2>/dev/null)
    major=$(echo "$macos_version" | cut -d. -f1)
    if [[ "$major" -ge 14 ]]; then
        pass "macOS $macos_version"
    else
        warn "macOS $macos_version (tested on 14+)"
    fi

    # Command Line Tools
    if xcode-select -p &>/dev/null; then
        pass "Command Line Tools installed"
    else
        fail "Command Line Tools not installed - run: xcode-select --install"
    fi
elif [[ "$DOTFILES_OS" == linux ]]; then
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release 2>/dev/null
        pass "$NAME"
    fi

    if command -v gcc &>/dev/null; then
        pass "build tools (gcc)"
    else
        warn "base-devel not installed - run: sudo pacman -S base-devel"
    fi
else
    fail "Not macOS or Linux"
fi

# Architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    pass "Apple Silicon (arm64)"
elif [[ "$ARCH" == "aarch64" ]]; then
    pass "ARM64 (aarch64)"
else
    pass "Intel/AMD ($ARCH)"
fi

echo ""

# ============================================================================
# Package Manager
# ============================================================================

echo "Package Manager:"

if [[ "$DOTFILES_OS" == macos ]]; then
    if command -v brew &>/dev/null; then
        brew_version=$(brew --version 2>/dev/null | head -1 | awk '{print $2}')
        pass "Homebrew $brew_version"
        
        critical_packages=("git" "zinit")
        for pkg in "${critical_packages[@]}"; do
            if brew list "$pkg" &>/dev/null; then
                pass "Brew package: $pkg"
            else
                fail "Brew package missing: $pkg"
            fi
        done

        autoupdate_status=$(brew autoupdate status 2>&1 || true)
        if [[ "$autoupdate_status" == *"installed and running"* ]]; then
            pass "Homebrew autoupdate running"
        else
            warn "Homebrew autoupdate not running - run: brew autoupdate start 86400 --upgrade --cleanup"
        fi
    else
        fail "Homebrew not installed"
    fi
elif [[ "$DOTFILES_OS" == linux ]]; then
    if command -v pacman &>/dev/null; then
        pass "Pacman"
        
        critical_packages=("git" "zsh" "zstd" "eza")
        for pkg in "${critical_packages[@]}"; do
            if pacman -Qi "$pkg" &>/dev/null; then
                pass "Package: $pkg"
            else
                fail "Package missing: $pkg"
            fi
        done

        if command -v yay &>/dev/null; then
            pass "yay (AUR helper)"
        else
            warn "yay not found"
        fi

        if systemctl --user is-active git-auto-pull.timer &>/dev/null; then
            pass "systemd timers running"
        else
            warn "systemd timers not active"
        fi
    else
        fail "Pacman not found"
    fi
fi

echo ""

# ============================================================================
# Automation Toolchain
# ============================================================================

echo "Automation Toolchain:"

required_cli_tools=("rg" "fd" "sd" "jq" "yq" "git" "gh")
for tool in "${required_cli_tools[@]}"; do
    if command -v "$tool" &>/dev/null; then
        tool_path=$(command -v "$tool")
        pass "CLI tool available: $tool ($tool_path)"
    else
        fail "CLI tool missing: $tool"
    fi
done

echo ""

# ============================================================================
# Dotfiles Structure
# ============================================================================

echo "Dotfiles Structure:"

DOTFILES_DIR="$HOME/dotfiles"

if [[ -d "$DOTFILES_DIR" ]]; then
    pass "Dotfiles directory exists"
    
    # Check key files
    [[ -f "$DOTFILES_DIR/install.sh" ]] && pass "install.sh present" || fail "install.sh missing"
    if [[ "$DOTFILES_OS" == macos ]]; then
        [[ -f "$DOTFILES_DIR/Brewfile" ]] && pass "Brewfile present" || fail "Brewfile missing"
    elif [[ "$DOTFILES_OS" == linux ]]; then
        [[ -f "$DOTFILES_DIR/pkglist/pacman.txt" ]] && pass "pkglist/pacman.txt present" || fail "pkglist/pacman.txt missing"
    fi
    [[ -d "$DOTFILES_DIR/zsh/functions" ]] && pass "Functions directory present" || fail "Functions directory missing"
else
    fail "Dotfiles directory missing at $DOTFILES_DIR"
fi

echo ""

# ============================================================================
# Shell Integration
# ============================================================================

echo "Shell Integration:"

# Check loader symlink
LOADER="$HOME/.config/zsh-dotfiles-loader.zsh"
if [[ -L "$LOADER" ]]; then
    target=$(readlink "$LOADER")
    if [[ "$target" == "$DOTFILES_DIR/zsh/functions.zsh" ]]; then
        pass "Loader symlinked correctly"
    else
        warn "Loader symlink points to: $target"
    fi
else
    fail "Loader not symlinked at $LOADER"
fi

# Check .zshrc sources loader
if [[ -f "$HOME/.zshrc" ]]; then
    if grep -q "zsh-dotfiles-loader.zsh" "$HOME/.zshrc" 2>/dev/null; then
        pass "Loader sourced in .zshrc"
    else
        fail "Loader not in .zshrc"
    fi
else
    fail ".zshrc not found"
fi

echo ""

# ============================================================================
# Powerlevel10k / Gitstatus
# ============================================================================

echo "Powerlevel10k / Gitstatus:"

# Check if powerlevel10k is installed
p10k_found=false
p10k_paths=(
    "$HOME/.zinit/plugins/romkatv---powerlevel10k"
    "/opt/homebrew/opt/powerlevel10k"
    "/usr/share/zsh/plugins/powerlevel10k"
)

for p10k_path in "${p10k_paths[@]}"; do
    if [[ -d "$p10k_path" ]]; then
        pass "Powerlevel10k installed at $p10k_path"
        p10k_found=true
        break
    fi
done

if [[ "$p10k_found" == false ]]; then
    fail "Powerlevel10k not found"
fi

# Check gitstatus binary
GITSTATUS_CACHE="$HOME/.cache/gitstatus"
case "$DOTFILES_OS" in
    macos) local gs_suffix="darwin" ;;
    linux) local gs_suffix="linux" ;;
esac
if [[ -f "$GITSTATUS_CACHE/gitstatusd-${gs_suffix}-$ARCH" ]]; then
    if [[ "$DOTFILES_OS" == macos ]]; then
        size=$(stat -f%z "$GITSTATUS_CACHE/gitstatusd-${gs_suffix}-$ARCH" 2>/dev/null || echo "unknown")
    else
        size=$(stat -c%s "$GITSTATUS_CACHE/gitstatusd-${gs_suffix}-$ARCH" 2>/dev/null || echo "unknown")
    fi
    pass "Gitstatus binary cached ($size bytes)"
else
    warn "Gitstatus binary not cached (will download on first run)"
fi

echo ""

# ============================================================================
# Functions Loading Test
# ============================================================================

echo "Functions Loading Test:"

# Test that functions can be sourced without errors
if [[ -f "$DOTFILES_DIR/zsh/functions.zsh" ]]; then
    # Source in subshell and capture any output
    errors=$(zsh -c "source $DOTFILES_DIR/zsh/functions.zsh 2>&1" 2>&1)
    
    if [[ -z "$errors" ]]; then
        pass "Functions source without errors"
    else
        fail "Functions produced errors: $errors"
    fi
    
    # Check specific functions exist
    source "$DOTFILES_DIR/zsh/functions.zsh" 2>/dev/null || true
    
    if type dotfiles-doctor &>/dev/null; then
        pass "Function dotfiles-doctor available"
    else
        fail "Function dotfiles-doctor not available"
    fi
else
    fail "Functions loader not found"
fi

echo ""

# ============================================================================
# Console Output Test (Critical for Instant Prompt)
# ============================================================================

echo "Console Output Test (Instant Prompt):"

# Test if zsh initialization produces any output
output=$(zsh -c 'source ~/.zshrc 2>&1' 2>&1)

if [[ -z "$output" ]]; then
    pass "No console output during initialization (instant prompt compatible)"
else
    fail "Console output detected during initialization:"
    echo ""
    echo "$output" | head -10
    echo ""
    echo "This will trigger Powerlevel10k instant prompt warning"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

echo "======================"
echo "Summary:"
echo "  ✅ Passed: $PASS"
echo "  ❌ Failed: $FAIL"
echo "  ⚠️  Warnings: $WARN"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "✅ All validations passed!"
    echo ""
    echo "Next steps:"
    if [[ "$DOTFILES_OS" == macos ]]; then
        echo "  • Run: dotfiles-doctor (comprehensive health check)"
        echo "  • Run: macos-defaults (apply system preferences)"
    elif [[ "$DOTFILES_OS" == linux ]]; then
        echo "  • Run: dotfiles-doctor (comprehensive health check)"
        echo "  • Run: pacup (update all packages)"
        echo "  • Run: kde-defaults (apply KDE Plasma preferences)"
    fi
    echo "  • Restart terminal to ensure clean startup"
    exit 0
else
    echo "❌ Some validations failed"
    echo ""
    echo "Troubleshooting:"
    if [[ "$DOTFILES_OS" == linux ]]; then
        echo "  • Run: ~/dotfiles/install.sh"
        echo "  • Check: ~/dotfiles/docs/install.md"
        echo "  • Diagnose: dotfiles-doctor"
    else
        echo "  • Re-run: ~/dotfiles/install.sh"
        echo "  • Check: ~/dotfiles/docs/install.md"
        echo "  • Diagnose: dotfiles-doctor"
    fi
    exit 1
fi
