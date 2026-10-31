#!/usr/bin/env bash
# ==============================================================================
# Script:      gdrive_upload.sh
# Category:    desktop
# Description: Quick upload of files and folders directly to Google Drive via Rclone.
# Target:      Linux workstation (Rclone, GNOME Nautilus)
# Requires:    bash, rclone, notify-send (optional)
# Usage:       gdrive-upload [OPTIONS] [FILE|DIR...]
# ==============================================================================
set -euo pipefail

SYNC_ROOT="${SYNC_SUBVOL:-$HOME/Remote/Synced}"
REMOTE_TARGET="${SYNC_REMOTE:-gdrive_dev:Synced}"
LOG_FILE="${SYNC_QUICK_LOG:-/tmp/rclone_quick_upload.log}"

show_help() {
    cat << EOF
Usage: gdrive-upload [OPTIONS] [FILE|DIR...]

Uploads selected files or directories directly to the Google Drive target
without executing a full bidirectional sync. Preserves relative directory hierarchy
for any path located within the local sync root.

Environment Defaults:
  SYNC_SUBVOL       $SYNC_ROOT
  SYNC_REMOTE       $REMOTE_TARGET
  SYNC_QUICK_LOG    $LOG_FILE

Options:
  -h, --help        Show this help message and exit

Integration:
  Can be invoked directly from the CLI or via GNOME Nautilus context menu
  (symlinked to ~/.local/share/nautilus/scripts/'Copy Selected to Google Drive').
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    show_help
    exit 0
fi

send_notify() {
    local urgency="$1"
    local title="$2"
    local message="$3"
    if command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" -a "Rclone" "$title" "$message" 2>/dev/null || true
    fi
}

RCLONE_BIN="$(type -P rclone 2>/dev/null || echo "/usr/bin/rclone")"
if [ ! -x "$RCLONE_BIN" ]; then
    echo "Error: 'rclone' binary not found in PATH or /usr/bin/rclone." >&2
    send_notify "critical" "Upload Error" "'rclone' binary not found."
    exit 1
fi

# Acquire items from Nautilus environment or command-line arguments
SELECTED_ITEMS=()
if [ -n "${NAUTILUS_SCRIPT_SELECTED_FILE_PATHS:-}" ]; then
    mapfile -t SELECTED_ITEMS <<< "$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS"
elif [ $# -gt 0 ]; then
    SELECTED_ITEMS=("$@")
fi

if [ ${#SELECTED_ITEMS[@]} -eq 0 ] || [ -z "${SELECTED_ITEMS[0]:-}" ]; then
    send_notify "low" "Quick Upload" "No files selected."
    echo "No files specified for upload." >&2
    exit 0
fi

for ITEM in "${SELECTED_ITEMS[@]}"; do
    [ -e "$ITEM" ] || continue

    # Ensure selected path resides within the Synced directory
    if [[ "$ITEM" != "$SYNC_ROOT"* ]]; then
        echo "Error: Target is outside Synced directory ($SYNC_ROOT): $ITEM" >&2
        send_notify "critical" "Upload Error" "Target is outside Synced directory:\n$(basename "$ITEM")"
        continue
    fi

    # Strip SYNC_ROOT prefix to preserve remote directory hierarchy
    REL_PATH="${ITEM#$SYNC_ROOT/}"

    if [ -d "$ITEM" ]; then
        echo "Uploading directory: $REL_PATH -> $REMOTE_TARGET/$REL_PATH"
        send_notify "low" "Uploading" "Syncing directory: $REL_PATH"
        if "$RCLONE_BIN" copy "$ITEM" "$REMOTE_TARGET/$REL_PATH" \
            --transfers 4 \
            --checkers 8 \
            --log-file="$LOG_FILE" \
            --log-level NOTICE; then
            send_notify "normal" "Upload Complete" "Directory uploaded: $REL_PATH"
        else
            send_notify "critical" "Upload Failed" "Failed to upload: $REL_PATH"
        fi
    else
        echo "Uploading file: $REL_PATH -> $REMOTE_TARGET/$REL_PATH"
        send_notify "low" "Uploading" "Uploading file: $REL_PATH"
        if "$RCLONE_BIN" copyto "$ITEM" "$REMOTE_TARGET/$REL_PATH" \
            --log-file="$LOG_FILE" \
            --log-level NOTICE; then
            send_notify "normal" "Upload Complete" "File uploaded: $REL_PATH"
        else
            send_notify "critical" "Upload Failed" "Failed to upload: $REL_PATH"
        fi
    fi
done
