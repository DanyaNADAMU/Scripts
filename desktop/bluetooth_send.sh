#!/usr/bin/env bash
# ==============================================================================
# Script:      bluetooth_send.sh
# Category:    desktop
# Description: Send files to paired phone via Bluetooth (blueman-sendto).
# Target:      Linux workstation (Blueman, GNOME Nautilus)
# Requires:    bash, blueman-sendto, notify-send (optional)
# Usage:       bluetooth-send [OPTIONS] [FILE...]
# ==============================================================================
set -euo pipefail

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/scripts"
MAC_FILE="$CONF_DIR/bluetooth_phone.mac"
CONF_FILE="$CONF_DIR/bluetooth_phone.conf"

show_help() {
    cat << EOF
Usage: bluetooth-send [OPTIONS] [FILE...]

Sends selected files to a paired mobile phone via Bluetooth using blueman-sendto.

Options:
  --setup [MAC]     Configure the target phone MAC address in $MAC_FILE
  -h, --help        Show this help message and exit

Configuration:
  Device MAC is resolved in the following priority order:
    1. BLUETOOTH_PHONE_MAC environment variable
    2. $MAC_FILE
    3. $CONF_FILE (PHONE_MAC=...)
    4. Auto-discovery of a single paired phone via bluetoothctl

Integration:
  Can be invoked directly from the CLI or via GNOME Nautilus context menu
  (symlinked to ~/.local/share/nautilus/scripts/'Send to Phone via Bluetooth').
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    show_help
    exit 0
fi

if [ "${1:-}" = "--setup" ]; then
    mac="${2:-}"
    mkdir -p "$CONF_DIR"
    if [ -n "$mac" ]; then
        echo "$mac" > "$MAC_FILE"
        echo "Saved Bluetooth phone MAC '$mac' to $MAC_FILE"
    else
        read -r -p "Enter phone Bluetooth MAC address (e.g. 12:34:56:78:9A:BC): " entered_mac
        if [ -n "$entered_mac" ]; then
            echo "$entered_mac" > "$MAC_FILE"
            echo "Saved Bluetooth phone MAC '$entered_mac' to $MAC_FILE"
        else
            echo "Aborted: No MAC address entered." >&2
            exit 1
        fi
    fi
    exit 0
fi

send_notify() {
    local urgency="$1"
    local title="$2"
    local message="$3"
    local icon="${4:-bluetooth}"
    if command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" -a "Bluetooth Transfer" "$title" "$message" -i "$icon" 2>/dev/null || true
    fi
}

PHONE_MAC="${BLUETOOTH_PHONE_MAC:-}"

# 1. Read from config file if available
if [ -z "$PHONE_MAC" ] && [ -f "$MAC_FILE" ]; then
    PHONE_MAC="$(grep -v '^[[:space:]]*#' "$MAC_FILE" | head -n 1 | tr -d '[:space:]')"
elif [ -z "$PHONE_MAC" ] && [ -f "$CONF_FILE" ]; then
    PHONE_MAC="$(grep -E '^PHONE_MAC=' "$CONF_FILE" 2>/dev/null | cut -d= -f2- | tr -d '\"'"' " || true)"
fi

# 2. Check bluetoothctl for a single paired phone device if unconfigured
if [ -z "$PHONE_MAC" ] && command -v bluetoothctl &>/dev/null; then
    paired_devices="$(bluetoothctl devices Paired 2>/dev/null || true)"
    phone_candidates="$(echo "$paired_devices" | grep -iE 'phone|android|xiaomi|galaxy|pixel|iphone' || true)"
    if [ -z "$phone_candidates" ]; then
        phone_candidates="$paired_devices"
    fi
    count="$(echo "$phone_candidates" | grep -c '^Device ' || true)"
    if [ "$count" -eq 1 ]; then
        PHONE_MAC="$(echo "$phone_candidates" | awk '{print $2}')"
    fi
fi

if [ -z "$PHONE_MAC" ]; then
    mkdir -p "$CONF_DIR"
    msg="Target phone MAC is not configured.\n\nSave your device MAC address into:\n$MAC_FILE\n(or run: bluetooth-send --setup <MAC>)"
    send_notify "critical" "Configuration Required" "$msg" "dialog-warning"
    echo -e "$msg" >&2
    exit 1
fi

if ! command -v blueman-sendto &>/dev/null; then
    send_notify "critical" "Transfer Error" "'blueman-sendto' is not installed." "network-error"
    echo "Error: 'blueman-sendto' binary not found in system PATH." >&2
    exit 1
fi

# Acquire files from arguments or Nautilus environment
FILES=()
if [ $# -gt 0 ]; then
    FILES=("$@")
elif [ -n "${NAUTILUS_SCRIPT_SELECTED_FILE_PATHS:-}" ]; then
    mapfile -t FILES <<< "$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS"
fi

if [ ${#FILES[@]} -eq 0 ] || [ -z "${FILES[0]:-}" ]; then
    send_notify "low" "Bluetooth Transfer" "No files selected." "dialog-information"
    echo "No files specified for transfer." >&2
    exit 0
fi

for file in "${FILES[@]}"; do
    [ -f "$file" ] || continue
    filename="$(basename "$file")"
    echo "Sending $filename to $PHONE_MAC via Bluetooth..."
    send_notify "low" "Sending to Phone" "$filename" "bluetooth"

    if blueman-sendto -d "$PHONE_MAC" "$file"; then
        send_notify "normal" "Sent" "$filename" "bluetooth"
    else
        send_notify "critical" "Sending Error" "$filename" "network-error"
    fi
done
