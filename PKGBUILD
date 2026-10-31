# Maintainer: DanyaNADAMU <git@nada.mu>
# Contributor: DanyaNADAMU <git@nada.mu>

pkgname=scripts-git
pkgver=1.1.0.r67.gd536fe9
pkgrel=1
pkgdesc="Unified manager and personal utilities ecosystem for nada.mu"
arch=('any')
url="https://github.com/DanyaNADAMU/Scripts"
license=('MIT')
depends=('bash' 'systemd' 'uv')
optdepends=(
    'rclone: for automated cloud backup utilities (backup-seadrive, backup-seafile, bisync-synced, gdrive-upload)'
    'openrgb: for keyboard RGB backlight profile switching (keylight)'
    'libnotify: for desktop notifications (bisync-synced)'
    'btrfs-progs: for snapshot protection during bidirectional sync (bisync-synced)'
    'blueman: for Bluetooth file transfer integration (bluetooth-send)'
    'nautilus: for GNOME Files context menu integration'
    'sshfs: for sshfs compatibility shim'
)
makedepends=('git')
provides=('scripts')
conflicts=('scripts')
source=("$pkgname::git+https://github.com/DanyaNADAMU/Scripts.git")
sha256sums=('SKIP')

pkgver() {
    local target_dir="$srcdir/$pkgname"
    [ ! -d "$target_dir" ] && target_dir="$srcdir/scripts"
    [ ! -d "$target_dir" ] && target_dir="${startdir:-.}"
    cd "$target_dir"
    local ver
    ver="$(git describe --long --tags --match 'v*' 2>/dev/null | sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g' || true)"
    if [ -z "$ver" ]; then
        ver="$(printf "1.1.0.r%s.g%s" "$(git rev-list --count HEAD 2>/dev/null || echo "0")" "$(git rev-parse --short=7 HEAD 2>/dev/null || echo "0000000")")"
    fi
    printf "%s" "$ver"
}

package() {
    local base_dir="$srcdir/$pkgname"
    [ ! -d "$base_dir" ] && base_dir="$srcdir/scripts"
    [ ! -d "$base_dir" ] && base_dir="${startdir:-.}"
    cd "$base_dir"

    # 1. Install CLI utilities declared in manifest.txt into /usr/bin
    install -dm755 "$pkgdir/usr/bin"
    while IFS=: read -r src cmd cat desc; do
        [[ -z "$src" || "$src" =~ ^[[:space:]]*# ]] && continue
        if [ "$cmd" = "sshfs" ]; then
            # Avoid conflict with official /usr/bin/sshfs provided by package 'sshfs'
            install -Dm755 "$src" "$pkgdir/usr/bin/sshfs-shim"
            continue
        fi
        if [ -f "$src" ]; then
            install -Dm755 "$src" "$pkgdir/usr/bin/$cmd"
        fi
    done < manifest.txt

    # Install unified scripts manager
    install -Dm755 scripts "$pkgdir/usr/bin/scripts"

    # 2. Install Linux manual pages
    install -dm755 "$pkgdir/usr/share/man/man1"
    for manfile in docs/man/man1/*.1; do
        if [ -f "$manfile" ]; then
            install -Dm644 "$manfile" "$pkgdir/usr/share/man/man1/"
        fi
    done

    # 3. Install shell completions (Bash, Zsh, Fish)
    install -dm755 "$pkgdir/usr/share/bash-completion/completions"
    install -dm755 "$pkgdir/usr/share/zsh/site-functions"
    install -dm755 "$pkgdir/usr/share/fish/vendor_completions.d"

    for f in completions/bash/*; do
        [ -f "$f" ] && install -Dm644 "$f" "$pkgdir/usr/share/bash-completion/completions/"
    done
    for f in completions/zsh/*; do
        [ -f "$f" ] && install -Dm644 "$f" "$pkgdir/usr/share/zsh/site-functions/"
    done
    for f in completions/fish/*; do
        [ -f "$f" ] && install -Dm644 "$f" "$pkgdir/usr/share/fish/vendor_completions.d/"
    done

    # 4. Install Pacman / ALPM hook
    install -dm755 "$pkgdir/usr/share/libalpm/hooks"
    install -Dm644 hooks/pacman/99scripts.hook "$pkgdir/usr/share/libalpm/hooks/99scripts.hook"
}
