#!/usr/bin/env bash
# ==============================================================================
# Script:      sshfs_shim.sh
# Category:    desktop
# Description: Compatibility shim stripping deprecated DSA (ssh-dss) and setting keepalive timeouts.
# Target:      Linux workstation (KDE Connect, OpenSSH 8.8+)
# Requires:    bash, sshfs
# Usage:       sshfs [sshfs-options] [user@]host:[dir] mountpoint
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Resolve the real underlying sshfs executable (prevent infinite recursion)
# ------------------------------------------------------------------------------
SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
REAL_SSHFS=""

while IFS= read -r candidate; do
    [ -z "$candidate" ] && continue
    cand_real="$(readlink -f "$candidate" 2>/dev/null || echo "$candidate")"
    if [ -x "$candidate" ] && [ "$cand_real" != "$SELF_PATH" ]; then
        REAL_SSHFS="$candidate"
        break
    fi
done < <(type -ap sshfs 2>/dev/null || true)

if [ -z "$REAL_SSHFS" ]; then
    for sys_bin in /usr/bin/sshfs /bin/sshfs; do
        if [ -x "$sys_bin" ] && [ "$(readlink -f "$sys_bin" 2>/dev/null)" != "$SELF_PATH" ]; then
            REAL_SSHFS="$sys_bin"
            break
        fi
    done
fi

# ------------------------------------------------------------------------------
# Self-documentation and help handling
# ------------------------------------------------------------------------------
if [ "${1:-}" = "--shim-info" ] || [ "${1:-}" = "--shim-version" ]; then
    cat << EOF
sshfs-shim (scripts/desktop/compat)
Role:           KDE Connect & OpenSSH 8.8+ compatibility shim & zombie-mount preventer
Target binary:  ${REAL_SSHFS:-"(not installed in system PATH)"}
Shim location:  $SELF_PATH
Features:
  - Strips deprecated DSA algorithms (+ssh-dss, ssh-dss)
  - Enforces SSH keepalive (ServerAliveInterval=5, ServerAliveCountMax=3)
  - Sets connection timeout (ConnectTimeout=5)
EOF
    exit 0
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    if [ -n "$REAL_SSHFS" ]; then
        exec "$REAL_SSHFS" "$@"
    else
        cat << 'EOF'
Usage: sshfs [user@]host:[dir] mountpoint [options]

KDE Connect DSA & Keepalive Compatibility Shim (scripts/desktop/compat)
Transparent wrapper around system sshfs that strips deprecated '+ssh-dss' algorithms
and configures aggressive keepalives to prevent zombie FUSE mounts (Input/output error).
Note: Underlying 'sshfs' binary is currently not installed on this system.
EOF
        exit 0
    fi
fi

if [ -z "$REAL_SSHFS" ]; then
    echo "Error: Underlying 'sshfs' binary not found in system paths." >&2
    exit 127
fi

# ------------------------------------------------------------------------------
# Sanitize arguments: strip deprecated DSA hostkey algorithms
# ------------------------------------------------------------------------------
sanitized_args=()
skip_next=false
args=("$@")

for ((i=0; i<${#args[@]}; i++)); do
    if [ "$skip_next" = true ]; then
        skip_next=false
        continue
    fi

    arg="${args[i]}"

    # If argument is separate '-o', check if subsequent parameter will become empty
    if [ "$arg" = "-o" ] && [ $((i + 1)) -lt ${#args[@]} ]; then
        next_arg="${args[i+1]}"
        next_cleaned="${next_arg//+ssh-dss,/}"
        next_cleaned="${next_cleaned//,+ssh-dss/}"
        next_cleaned="${next_cleaned//+ssh-dss/}"
        next_cleaned="${next_cleaned//ssh-dss,/}"
        next_cleaned="${next_cleaned//,ssh-dss/}"
        next_cleaned="${next_cleaned//ssh-dss/}"

        if [[ "$next_cleaned" =~ ^HostKeyAlgorithms=$ ]]; then
            skip_next=true
            continue
        fi
    fi

    # Remove +ssh-dss and ssh-dss in all common delimiter positions
    arg="${arg//+ssh-dss,/}"
    arg="${arg//,+ssh-dss/}"
    arg="${arg//+ssh-dss/}"
    arg="${arg//ssh-dss,/}"
    arg="${arg//,ssh-dss/}"
    arg="${arg//ssh-dss/}"

    # Drop dangling empty HostKeyAlgorithms options (e.g. -oHostKeyAlgorithms=)
    if [[ "$arg" =~ ^(-o\s*)?HostKeyAlgorithms=$ ]]; then
        continue
    fi

    [ -z "$arg" ] && continue
    sanitized_args+=("$arg")
done

# ------------------------------------------------------------------------------
# Inject aggressive keepalive and timeout options to prevent zombie FUSE mounts
# ------------------------------------------------------------------------------
has_server_alive=false
has_connect_timeout=false

for a in "${sanitized_args[@]}"; do
    if [[ "$a" =~ ServerAliveInterval ]]; then
        has_server_alive=true
    fi
    if [[ "$a" =~ ConnectTimeout ]]; then
        has_connect_timeout=true
    fi
done

if [ "$has_server_alive" = false ]; then
    sanitized_args+=(
        "-o" "ServerAliveInterval=5"
        "-o" "ServerAliveCountMax=3"
    )
fi

if [ "$has_connect_timeout" = false ]; then
    sanitized_args+=(
        "-o" "ConnectTimeout=5"
    )
fi

if [ ${#sanitized_args[@]} -gt 0 ]; then
    exec "$REAL_SSHFS" "${sanitized_args[@]}"
else
    exec "$REAL_SSHFS"
fi
