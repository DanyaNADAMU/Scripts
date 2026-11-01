#!/usr/bin/env bash
# ==============================================================================
# Script:      bisync_synced.sh
# Category:    desktop
# Description: Bidirectional Google Drive sync with Btrfs snapshot protection.
# Target:      Linux workstation (Btrfs, Rclone)
# Requires:    bash, rclone, btrfs-progs (optional), notify-send (optional)
# Usage:       bisync-synced [OPTIONS]
# ==============================================================================
set -euo pipefail

LOCK_FILE="${SYNC_LOCK_FILE:-/tmp/rclone_bisync.lock}"
SUBVOL="${SYNC_SUBVOL:-$HOME/Remote/Synced}"
SNAP_DIR="${SYNC_SNAP_DIR:-$HOME/.local/share/gdrive_snapshots}"
FILTER_FILE="${SYNC_FILTER_FILE:-$HOME/.config/rclone/bisync-synced.filter}"
LOG_FILE="${SYNC_LOG_FILE:-/tmp/rclone_bisync.log}"
REMOTE_TARGET="${SYNC_REMOTE:-gdrive_dev:Synced}"

show_help() {
    cat << EOF
Usage: bisync-synced [OPTIONS]

Bidirectional Google Drive synchronization using Rclone with automatic
Btrfs snapshot protection, deduplication, and desktop notifications.

Configuration Defaults (override via environment):
  SYNC_SUBVOL       $SUBVOL
  SYNC_REMOTE       $REMOTE_TARGET
  SYNC_SNAP_DIR     $SNAP_DIR
  SYNC_FILTER_FILE  $FILTER_FILE
  SYNC_LOG_FILE     $LOG_FILE

Options:
  --resync          Perform initial resync (passes --resync to rclone bisync)
  --dry-run         Perform trial run without transferring or writing data
  --status          Show last sync log entries and lock state
  -h, --help        Show this help message and exit
EOF
}

send_notify() {
    local urgency="$1"
    local title="$2"
    local message="$3"
    if command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" -a "Rclone" "$title" "$message" 2>/dev/null || true
    fi
}

EXTRA_RCLONE_FLAGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --resync)
            EXTRA_RCLONE_FLAGS+=("--resync")
            shift
            ;;
        --dry-run)
            EXTRA_RCLONE_FLAGS+=("--dry-run")
            shift
            ;;
        --status)
            echo "Lock file: $LOCK_FILE"
            if [ -f "$LOCK_FILE" ]; then
                echo "Lock file exists."
            fi
            if [ -f "$LOG_FILE" ]; then
                echo "--- Recent Log ($LOG_FILE) ---"
                tail -n 20 "$LOG_FILE"
            else
                echo "No log file found at $LOG_FILE"
            fi
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

# Locate rclone binary
RCLONE_BIN="$(type -P rclone 2>/dev/null || echo "/usr/bin/rclone")"
if [ ! -x "$RCLONE_BIN" ]; then
    echo "Error: 'rclone' binary not found in PATH or /usr/bin/rclone." >&2
    send_notify "critical" "Google Drive Sync" "Error: rclone binary not found."
    exit 1
fi

# Ensure target local directory exists
if [ ! -d "$SUBVOL" ]; then
    echo "Error: Local sync directory '$SUBVOL' does not exist." >&2
    send_notify "critical" "Google Drive Sync" "Error: Local sync directory missing: $SUBVOL"
    exit 1
fi

# Ensure check-access token exists locally if check-access is enabled
if [ ! -f "$SUBVOL/RCLONE_TEST" ]; then
    touch "$SUBVOL/RCLONE_TEST" 2>/dev/null || true
fi

# Prevent concurrent runs via non-blocking file lock
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    send_notify "normal" "Google Drive Sync" "Sync is already running."
    echo "Sync is already in progress (locked via $LOCK_FILE)." >&2
    exit 1
fi

send_notify "low" "Google Drive Sync" "Starting bidirectional sync..."

if [ -t 1 ]; then
    echo "==> Starting bidirectional sync ($SUBVOL <-> $REMOTE_TARGET)..."
    echo "    Scanning files across Google Drive and local filesystem (takes ~30-60s)..."
fi

# Create read-only Btrfs snapshot if directory is on a Btrfs subvolume
if command -v btrfs &>/dev/null && btrfs subvolume show "$SUBVOL" &>/dev/null; then
    mkdir -p "$SNAP_DIR"
    SNAP_NAME="sync-$(date +%Y%m%d_%H%M%S)"
    if btrfs subvolume snapshot -r "$SUBVOL" "$SNAP_DIR/$SNAP_NAME" >/dev/null 2>&1; then
        # Maintain only the last 5 snapshots
        shopt -s nullglob
        snaps=("$SNAP_DIR"/sync-*)
        shopt -u nullglob
        if [ ${#snaps[@]} -gt 5 ]; then
            IFS=$'\n' sorted=($(printf '%s\n' "${snaps[@]}" | sort -r))
            unset IFS
            for ((k=5; k<${#sorted[@]}; k++)); do
                btrfs subvolume delete "${sorted[k]}" >/dev/null 2>&1 || true
            done
        fi
    fi
else
    # Non-Btrfs fallback: skip snapshot creation gracefully
    :
fi

# Build rclone arguments
RCLONE_ARGS=(
    "bisync"
    "$REMOTE_TARGET"
    "$SUBVOL"
    "--resilient"
    "--recover"
    "--check-access"
    "--bwlimit" "15M"
    "--transfers" "3"
    "--checkers" "6"
    "--tpslimit" "10"
    "--log-file=$LOG_FILE"
    "--log-level" "NOTICE"
)

if [ -f "$FILTER_FILE" ]; then
    RCLONE_ARGS+=("--filter-from" "$FILTER_FILE")
fi

if [ ${#EXTRA_RCLONE_FLAGS[@]} -gt 0 ]; then
    RCLONE_ARGS+=("${EXTRA_RCLONE_FLAGS[@]}")
fi

if "$RCLONE_BIN" "${RCLONE_ARGS[@]}"; then
    send_notify "normal" "Google Drive Sync" "Sync completed successfully."
else
    send_notify "critical" "Google Drive Sync" "Sync failed. Check log: $LOG_FILE"
    exit 1
fi
