#!/usr/bin/env bash
# ==============================================================================
# Script:      install.sh
# Description: Bootstrap launcher for the unified 'scripts' manager.
# Usage:       ./install.sh [options]  OR  curl -fsSL <url>/install.sh | bash
# ==============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || echo "")"

is_arch_like() {
    [ -f /etc/arch-release ] && return 0
    [ -f /etc/cachyos-release ] && return 0
    if [ -f /etc/os-release ]; then
        if grep -qE '^ID(_LIKE)?=.*(arch|cachyos|manjaro|endeavouros)' /etc/os-release; then
            return 0
        fi
    fi
    command -v pacman >/dev/null 2>&1 && return 0
    return 1
}

# Parse options
MODE="auto"
WITH_OPTDEPENDS=false
FORWARD_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --native|--makepkg|--pacman)
            MODE="native"
            ;;
        --user|--symlink|--standard)
            MODE="user"
            ;;
        --with-optdepends)
            WITH_OPTDEPENDS=true
            ;;
        -h|--help|help)
            echo "Usage: ./install.sh [options]"
            echo ""
            echo "Bootstrap installer for the nada.mu scripts ecosystem."
            echo ""
            echo "Options:"
            echo "  --native, --makepkg    Build and install as native Arch/CachyOS package (makepkg -si)"
            echo "  --user                 Install into ~/.local/bin without root privileges"
            echo "  --with-optdepends      Install optional dependencies via pacman on Arch/CachyOS"
            echo "  --category <cat>       Filter utilities: all, server, desktop, media"
            echo "  --scope <scope>        Target directory scope: user or system"
            echo "  -y, --yes              Assume yes to all prompts"
            echo "  -h, --help             Show this help synopsis"
            exit 0
            ;;
        *)
            FORWARD_ARGS+=("$arg")
            ;;
    esac
done

# Optional dependencies for Arch / CachyOS
install_arch_optdepends() {
    local opt_pkgs=("rclone" "openrgb" "libnotify" "btrfs-progs" "blueman")
    echo "==> Installing optional dependencies via pacman: ${opt_pkgs[*]}"
    if [ "$EUID" -eq 0 ]; then
        pacman -S --needed --noconfirm "${opt_pkgs[@]}" || true
    else
        sudo pacman -S --needed --noconfirm "${opt_pkgs[@]}" || true
    fi
}

run_native_install() {
    if ! command -v makepkg >/dev/null 2>&1; then
        echo "Error: 'makepkg' not found. Please install base-devel: sudo pacman -S --needed base-devel git" >&2
        exit 1
    fi

    if [ "$WITH_OPTDEPENDS" = true ]; then
        install_arch_optdepends
    fi

    if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/PKGBUILD" ]; then
        echo "==> Building and installing native package from local repository..."
        cd "$SELF_DIR"
        mkdir -p src
        ln -sfn "$SELF_DIR" src/scripts
        makepkg -ef -si
        exit 0
    else
        echo "==> Fetching repository and building native package..."
        local build_tmp
        build_tmp="$(mktemp -d -t scripts-build.XXXXXX)"
        trap 'rm -rf "$build_tmp"' EXIT INT TERM
        git clone https://github.com/DanyaNADAMU/Scripts.git "$build_tmp"
        cd "$build_tmp"
        makepkg -si
        exit 0
    fi
}

# Interactive Arch/CachyOS auto-detection
if [ "$MODE" = "auto" ] && is_arch_like; then
    # If running interactively in terminal with no conflicting forward commands
    if [ -t 0 ] && [ -t 1 ] && [ ${#FORWARD_ARGS[@]} -eq 0 ]; then
        echo ""
        echo -e "\033[1;36m==>\033[0m \033[1mArch Linux / CachyOS environment detected!\033[0m"
        echo "    Choose your preferred installation mode:"
        echo "      1) Native ALPM package via pacman/makepkg [Recommended for Arch/CachyOS]"
        echo "      2) User-space symlinks into ~/.local/bin [Standard / Developer mode]"
        echo ""
        read -r -p "    Select [1/2] (default: 1): " choice </dev/tty || choice="1"
        if [ -z "$choice" ] || [ "$choice" = "1" ]; then
            MODE="native"
        else
            MODE="user"
        fi
    fi
fi

if [ "$MODE" = "native" ]; then
    run_native_install
fi

# Fallback / User Space installation via scripts manager
ARGS=()
if [ ${#FORWARD_ARGS[@]} -eq 0 ]; then
    ARGS=("update")
else
    case "${FORWARD_ARGS[0]}" in
        update|sync|install|list|uninstall|doctor|pkgbuild|help|-h|--help)
            ARGS=("${FORWARD_ARGS[@]}")
            ;;
        *)
            ARGS=("update" "${FORWARD_ARGS[@]}")
            ;;
    esac
fi

if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/scripts" ]; then
    exec "$SELF_DIR/scripts" "${ARGS[@]}"
fi

# Remote bootstrap mode (e.g. curl -fsSL .../install.sh | bash)
GITHUB_RAW="https://raw.githubusercontent.com/DanyaNADAMU/Scripts/main"
COMMIT_SHA="$(curl -fsSL --connect-timeout 2 --max-time 4 "https://api.github.com/repos/DanyaNADAMU/Scripts/commits/main" 2>/dev/null | grep '"sha"' | head -n 1 | cut -d'"' -f4 || echo "")"
if [ -n "$COMMIT_SHA" ]; then
    GITHUB_RAW="https://raw.githubusercontent.com/DanyaNADAMU/Scripts/$COMMIT_SHA"
fi

TMP_SCRIPTS="$(mktemp -t scripts-bootstrap.XXXXXX)"
cleanup() {
    rm -f "$TMP_SCRIPTS"
}
trap cleanup EXIT INT TERM

if ! curl -fsSL --connect-timeout 5 --max-time 30 "$GITHUB_RAW/scripts" -o "$TMP_SCRIPTS"; then
    echo "Error: Failed to download bootstrap scripts manager." >&2
    exit 1
fi

chmod +x "$TMP_SCRIPTS"
"$TMP_SCRIPTS" "${ARGS[@]}"
cleanup
