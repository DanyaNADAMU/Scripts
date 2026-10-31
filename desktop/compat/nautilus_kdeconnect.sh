#!/usr/bin/env bash
# ==============================================================================
# Script:      nautilus_kdeconnect.sh
# Category:    desktop
# Description: Translates kdeconnect:// URLs and kioexec paths into local FUSE mounts for Nautilus.
# Target:      Linux workstation (GNOME, KDE Connect)
# Requires:    bash, nautilus
# Usage:       nautilus-kdeconnect [OPTIONS] [URI|PATH...]
# ==============================================================================
set -euo pipefail

show_help() {
    cat << 'EOF'
Usage: nautilus-kdeconnect [OPTIONS] [URI|PATH...]

Compatibility bridge for opening KDE Connect device storage in GNOME Nautilus.

Translates 'kdeconnect://<device-id>' URIs and 'kioexec' cache paths into
active local FUSE mountpoints located at /run/user/$UID/<device-id>/...,
then forwards arguments to the native Nautilus file manager.

Options:
  -r, --reset [ID]   Perform emergency reset of hanging/zombie FUSE mounts
                     (fusermount3 -u -z, pkill dead sshfs, and remount via kdeconnect-cli)
  -h, --help         Show this help message and exit
EOF
}

is_zombie_mount() {
    local mnt="$1"
    # Check if mount point is listed in /proc/mounts
    if grep -q "[[:space:]]${mnt%/}[[:space:]]" /proc/mounts 2>/dev/null; then
        # If stat fails or hangs for > 1 second, it's a dead FUSE zombie
        if ! timeout 1 stat "$mnt" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

reset_mount() {
    local dev_root="$1"
    local dev_id="${2:-}"

    echo "[!] Clearing zombie FUSE mount at $dev_root..." >&2
    # Lazy unmount dead FUSE descriptor
    fusermount3 -u -z "$dev_root" 2>/dev/null || fusermount -u -z "$dev_root" 2>/dev/null || true

    # Terminate orphan sshfs processes associated with this mount or device
    if [ -n "$dev_id" ]; then
        pkill -9 -f "sshfs.*${dev_id}" 2>/dev/null || true
    fi
    pkill -9 -f "sshfs.*${dev_root}" 2>/dev/null || true

    # Attempt to remount via kdeconnect-cli if available
    if [ -n "$dev_id" ] && command -v kdeconnect-cli >/dev/null 2>&1; then
        echo "[i] Requesting remount for device $dev_id via kdeconnect-cli..." >&2
        kdeconnect-cli -d "$dev_id" --mount 2>/dev/null || true
        # Wait up to 3 seconds for mount to appear
        for _ in 1 2 3; do
            if grep -q "[[:space:]]${dev_root%/}[[:space:]]" /proc/mounts 2>/dev/null && timeout 1 stat "$dev_root" >/dev/null 2>&1; then
                echo "[✓] Device $dev_id remounted successfully." >&2
                break
            fi
            sleep 1
        done
    fi
}

current_uid="${UID:-$(id -u)}"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    show_help
    exit 0
fi

if [ "${1:-}" = "-r" ] || [ "${1:-}" = "--reset" ]; then
    target_dev="${2:-}"
    if [ -n "$target_dev" ]; then
        reset_mount "/run/user/${current_uid}/${target_dev}" "$target_dev"
    else
        echo "[i] Scanning for KDE Connect zombie mounts under /run/user/${current_uid}..." >&2
        found_any=false
        shopt -s nullglob
        for d in "/run/user/${current_uid}"/*; do
            dev_name="$(basename "$d")"
            if grep -q "[[:space:]]${d%/}[[:space:]]" /proc/mounts 2>/dev/null; then
                found_any=true
                if is_zombie_mount "$d"; then
                    echo "[!] Found zombie mount: $d" >&2
                    reset_mount "$d" "$dev_name"
                else
                    echo "[✓] Healthy mount: $d" >&2
                fi
            fi
        done
        shopt -u nullglob
        if [ "$found_any" = false ]; then
            echo "[i] No active mounts found under /run/user/${current_uid}." >&2
        fi
    fi
    exit 0
fi

# Locate the real nautilus binary, avoiding self-referential execution
SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
REAL_NAUTILUS=""

while IFS= read -r candidate; do
    [ -z "$candidate" ] && continue
    cand_real="$(readlink -f "$candidate" 2>/dev/null || echo "$candidate")"
    if [ -x "$candidate" ] && [ "$cand_real" != "$SELF_PATH" ]; then
        REAL_NAUTILUS="$candidate"
        break
    fi
done < <(type -ap nautilus 2>/dev/null || true)

if [ -z "$REAL_NAUTILUS" ]; then
    for sys_bin in /usr/bin/nautilus /bin/nautilus; do
        if [ -x "$sys_bin" ] && [ "$(readlink -f "$sys_bin" 2>/dev/null)" != "$SELF_PATH" ]; then
            REAL_NAUTILUS="$sys_bin"
            break
        fi
    done
fi

if [ -z "$REAL_NAUTILUS" ]; then
    echo "Error: 'nautilus' binary not found in system PATH or standard locations." >&2
    exit 1
fi

sanitized_args=()

for arg in "$@"; do
    if [[ "$arg" =~ ^kdeconnect://([^/]+)(/.*)?$ ]]; then
        dev_id="${BASH_REMATCH[1]}"
        subpath="${BASH_REMATCH[2]:-}"
        dev_root="/run/user/${current_uid}/${dev_id}"

        # Check and heal zombie mount if necessary
        if is_zombie_mount "$dev_root"; then
            reset_mount "$dev_root" "$dev_id"
        fi

        if [[ "$subpath" =~ ^/storage/emulated/0 ]]; then
            target="${dev_root}${subpath}"
        else
            target="${dev_root}/storage/emulated/0${subpath}"
        fi

        [ ! -e "$target" ] && target="${dev_root}${subpath}"
        [ ! -e "$target" ] && target="${dev_root}"

        sanitized_args+=("$target")
    elif [[ "$arg" =~ /\.cache/kioexec/krun/ ]]; then
        # Check and heal zombie mounts if necessary
        shopt -s nullglob
        for dev_dir in /run/user/"${current_uid}"/[0-9a-fA-F]*; do
            if is_zombie_mount "$dev_dir"; then
                reset_mount "$dev_dir" "$(basename "$dev_dir")"
            fi
        done

        # Resolve active KDE Connect mount if called through kioexec
        phone_target=""
        candidates=(/run/user/"${current_uid}"/*/storage/emulated/0)
        if [ ${#candidates[@]} -gt 0 ] && [ -d "${candidates[0]}" ]; then
            phone_target="${candidates[0]}"
        else
            fallback=(/run/user/"${current_uid}"/[0-9a-fA-F]*)
            if [ ${#fallback[@]} -gt 0 ] && [ -d "${fallback[0]}" ]; then
                phone_target="${fallback[0]}"
            fi
        fi
        shopt -u nullglob

        if [ -n "$phone_target" ] && [ -d "$phone_target" ]; then
            sanitized_args+=("$phone_target")
            # Clean up dummy kioexec directory
            kio_dir="$(dirname "$arg")"
            if [[ "$kio_dir" =~ /\.cache/kioexec/krun/ ]] && [ -d "$kio_dir" ]; then
                rm -rf "$kio_dir"
            fi
        else
            sanitized_args+=("$arg")
        fi
    else
        sanitized_args+=("$arg")
    fi
done

if [ ${#sanitized_args[@]} -gt 0 ]; then
    exec "$REAL_NAUTILUS" "${sanitized_args[@]}"
else
    exec "$REAL_NAUTILUS"
fi
