# desktop

Scripts designed for local workstations, laptop environments, window managers (Wayland, Niri), audio systems, display configuration, and desktop workflows.

## Utilities

### `backup-seadrive`
Resilient, encrypted incremental backup from a local SeaDrive mount (`~/SeaDrive/My Libraries`) directly to Google Drive (`gdrive-crypt:SeafileBackup`) using Rclone and systemd user timers.

* **Zero-Knowledge Encryption:** Encrypted on-the-fly in RAM with XSalsa20 + Poly1305 before transmission.
* **Offline Boot Resilience:** Automatically defers execution when booting without internet or before SeaDrive is mounted, retrying every 15 minutes until connectivity is established.
* **Smart Daily Throttling:** Maintains state in `~/.local/state/scripts/backup-seadrive.last` to ensure backups run once per day (~20 hour cooldown) without duplicate runs or CPU waste.
* **Zero-Data-Loss Safety:** Verifies source directory existence and non-empty status before initiating sync to prevent accidental deletion on the remote.

```bash
# Set up resilient systemd user timer
backup-seadrive --setup-timer

# Check backup status, cooldown, and prerequisites
backup-seadrive --status

# Force immediate manual backup
backup-seadrive --force
```

---

### `bisync-synced`
Resilient bidirectional synchronization between local storage (`$HOME/Remote/Synced`) and Google Drive (`gdrive_dev:Synced`) using Rclone with instantaneous Btrfs snapshot rollback protection and desktop notifications.

* **Btrfs Snapshot Safeguard:** Automatically captures a timestamped read-only Btrfs snapshot (`$HOME/.local/share/gdrive_snapshots/sync-YYYYMMDD_HHMMSS`) before initiating bidirectional sync. If files are accidentally deleted or conflicted on the remote side, local snapshots preserve previous revisions.
* **Automatic Snapshot Retention:** Retains the 5 most recent snapshots and automatically prunes older snapshots.
* **Non-Blocking Flock Protection:** Prevents duplicate concurrent synchronization runs via non-blocking file locking on descriptor 200.
* **Desktop Notifications:** Real-time feedback via `notify-send` for start, completion, concurrency conflicts, and failures.
* **Graceful Fallback:** If the target directory is not located on a Btrfs filesystem, snapshot creation is skipped with an informational message and the bidirectional sync proceeds normally.

```bash
# Run standard bidirectional sync
bisync-synced

# Perform baseline resync (e.g. after adding filter rules or recovering conflict)
bisync-synced --resync

# Dry run simulation
bisync-synced --dry-run

# Inspect lock state and sync log
bisync-synced --status
```

---

### `gdrive-upload`
Rapid direct upload of selected files and folders to Google Drive via Rclone without running a full bidirectional sync.

* **Hierarchy Preservation:** Strips the local sync root (`$HOME/Remote/Synced`) and reconstructs the relative subfolder tree on the remote target (`gdrive_dev:Synced`).
* **Dual CLI & GUI Operation:** Reads file arguments from the terminal (`$@`) or directly from GNOME Nautilus selection environment variables (`$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS`).
* **Desktop Notifications:** Real-time feedback via `notify-send`.

```bash
# Upload specific files or folders from the terminal
gdrive-upload ~/Remote/Synced/Documents/Report.pdf

# Or trigger from Nautilus context menu:
# Right-click file(s) inside ~/Remote/Synced -> Scripts -> 'Copy Selected to Google Drive'
```

---

### `bluetooth-send`
High-speed wireless file transfer to a paired mobile phone via Bluetooth using `blueman-sendto`.

* **Zero Hardcoded Secrets:** No personal device MAC addresses or user identities are stored in the git repository.
* **Dynamic Resolution:** Automatically checks `$BLUETOOTH_PHONE_MAC`, `~/.config/scripts/bluetooth_phone.mac`, `~/.config/scripts/bluetooth_phone.conf`, or auto-discovers a single paired phone via `bluetoothctl`.
* **Built-in Setup Command:** Easy one-time setup via `bluetooth-send --setup <MAC>`.

```bash
# Configure phone MAC once:
bluetooth-send --setup 48:87:59:C8:70:D9

# Send file directly from terminal:
bluetooth-send photo.jpg

# Or trigger from Nautilus context menu:
# Right-click file(s) -> Scripts -> 'Send to Phone via Bluetooth'
```

---

### `keylight`
High-performance cyclic keyboard RGB backlight profile switcher using the OpenRGB SDK. Specially tailored for MSI Mystic Light controllers (MS-1565).

* **Direct Socket Acceleration (< 50ms):** Communicates directly with the OpenRGB background SDK server on `127.0.0.1:6742` over a raw TCP socket, bypassing CLI startup delays and switching lighting presets virtually instantaneously (~40ms for single presets, ~250ms for 4-zone gradients).
* **Automatic CLI Fallback:** If the OpenRGB background daemon is stopped, `keylight` automatically falls back to executing the OpenRGB CLI.
* **Hardware Quirk Workaround:** MSI MS-1565 laptop controllers are write-only (no hardware readback) and expose the 4 keyboard zones as mutually exclusive driver *modes* (`Static zone 1` .. `Static zone 4`) instead of zones. Because OpenRGB `.json` profile files only store a single active mode per device, standard profile loading fails and blanks the keyboard. `keylight` sequences raw mode packets to bypass this driver flaw.
* **Stateful Cycling:** Maintains the active state in `${XDG_CACHE_HOME:-$HOME/.cache}/keylight-current-profile`, allowing rapid cycling across presets via a single hotkey.
* **Presets:**
  * `off`: Complete backlight shutoff.
  * `night`: 4-zone emerald-to-olive forest gradient at 40% brightness (`#006644`, `#006626`, `#1E6610`, `#386608`).
  * `cyan`: Static neon cyan illumination at 40% brightness (`#00FFFF`).
  * `white`: Static soft white illumination at 35% brightness (`#FFFFFF`).

```bash
# Cycle to the next profile in sequence (off -> night -> cyan -> white)
keylight

# Switch directly to a specific profile
keylight night

# View currently active profile
keylight --current

# List available profiles with active indicator
keylight --list
```

#### Window Manager Keybinding Example (Niri / Sway / Hyprland)
Bind keyboard shortcuts (e.g. `Fn + F8`, hardware brightness keys, or `Mod + Shift + B`) to `keylight` in your compositor configuration:
```kdl
// Niri example (~/.config/niri/config.kdl)
binds {
    // Cycle presets via dedicated media keys or custom shortcut
    XF86KbdBrightnessUp   allow-when-locked=true { spawn "keylight" "--next"; }
    XF86KbdBrightnessDown allow-when-locked=true { spawn "keylight" "off"; }
    Mod+Shift+B                                  { spawn "keylight"; }
}
```

---

## Compatibility Shims & Workarounds (`compat/`)

This directory houses targeted integration shims and protocol bridges that resolve upstream bugs, missing protocol support, or deprecations between independent desktop software packages (e.g., KDE Connect, GNOME Nautilus, OpenSSH).

### `nautilus-kdeconnect`
Seamless file manager bridge allowing GNOME **Nautilus** to open storage shares mounted by **KDE Connect**, with built-in zombie FUSE mount recovery.

* **The Problem:** KDE Connect opens devices via KDE-specific `kdeconnect://<device-id>` URLs or through temporary `kioexec` directories (`~/.cache/kioexec/krun/...`). Nautilus does not support KIO protocols, resulting in failed launches or blank dummy folders. Furthermore, when Android drops connections, the mount degrades into a dead state (`d---------`, `Input/output error`), hanging Nautilus.
* **The Solution:** Intercepts arguments, dynamically translates them to the active local FUSE mountpoint (`/run/user/$UID/<device-id>/storage/emulated/0` or `/run/user/$UID/<device-id>`), prunes dummy `kioexec` cache directories, and automatically detects and clears zombie FUSE mounts before launching Nautilus.

```bash
# Direct launch
nautilus-kdeconnect kdeconnect://<device-id>

# Emergency reset & remount of hanging/zombie mounts
nautilus-kdeconnect --reset
nautilus-kdeconnect --reset <device-id>

# Register as default scheme handler for kdeconnect:// links:
xdg-mime default nautilus-kdeconnect.desktop x-scheme-handler/kdeconnect
```

---

### `sshfs` (DSA & Keepalive Compatibility Shim)
Transparent PATH shim intercepting calls to `sshfs` to sanitize obsolete algorithm options and enforce aggressive keepalive timeouts to prevent dead FUSE mounts.

* **The Problem:**
  1. Modern OpenSSH (8.8+) completely disables and rejects deprecated DSA signatures (`ssh-dss`) by default. KDE Connect hardcodes `-oHostKeyAlgorithms=+ssh-dss` when mounting mobile storage via SFTP, causing mounts to fail immediately.
  2. By default, `sshfs` does not set SSH keepalives (`ServerAliveInterval=0`). When Android (MIUI / HyperOS Doze mode) sleeps the Wi-Fi chip or suspends the KDE Connect background service, the TCP socket dies silently. The Linux kernel waits indefinitely, locking all file I/O into uninterruptible D-state and producing `d---------` / `Input/output error (os error 5)` zombie mounts.
* **The Solution:** Installed into `/usr/local/bin/sshfs` (or `~/.local/bin/sshfs`), taking precedence in `$PATH` over `/usr/bin/sshfs`:
  * Dynamically discovers the real underlying `sshfs` binary (preventing recursive execution).
  * Strips deprecated `+ssh-dss` and dangling empty options.
  * Injects aggressive keepalive parameters:
    * `-o ServerAliveInterval=5`: Sends a keepalive ping every 5 seconds.
    * `-o ServerAliveCountMax=3`: Drops dead connections after 15 seconds of unresponsiveness.
    * `-o ConnectTimeout=5`: Fails quickly if device is unreachable.
* **Retirement Criteria:** This shim can be removed once KDE Connect removes hardcoded `ssh-dss` host key algorithms in upstream releases and provides native keepalive settings.

```bash
# Check shim status, injected features, and target binary:
sshfs --shim-info
```

---

## Nautilus Context Menu Integration

Interactive actions integrated directly into the GNOME Nautilus file manager right-click context menu (**Scripts** / **Скрипты**).

All items in `~/.local/share/nautilus/scripts/` are lightweight symlinks pointing directly to the canonical CLI utilities installed in `$BIN_DIR` (`/usr/local/bin` or `~/.local/bin`):
* `'BiSync All Synced'` $\to$ `$BIN_DIR/bisync-synced`
* `'Copy Selected to Google Drive'` $\to$ `$BIN_DIR/gdrive-upload`
* `'Send to Phone via Bluetooth'` $\to$ `$BIN_DIR/bluetooth-send`

### Management via CLI
Nautilus symlinks are automatically created during `scripts update` (both in user scope and when running with `sudo`, where the manager detects `$SUDO_USER` and sets proper file ownership). They can also be inspected and managed explicitly:

```bash
# Synchronize context menu symlinks into ~/.local/share/nautilus/scripts/
scripts nautilus install

# Inspect active symlinks and targets
scripts nautilus list

# Remove context menu symlinks
scripts nautilus uninstall
```

### Context Menu Actions

#### 1. `BiSync All Synced`
* **Trigger:** Right-click inside any Nautilus folder $\to$ **Scripts** $\to$ **BiSync All Synced**.
* **Target:** `bisync-synced`
* **Action:** Captures a Btrfs snapshot, executes bidirectional Google Drive sync, and displays real-time desktop status notifications.

#### 2. `Copy Selected to Google Drive`
* **Trigger:** Select file(s) or folder(s) located within `$HOME/Remote/Synced` in Nautilus $\to$ **Scripts** $\to$ **Copy Selected to Google Drive**.
* **Target:** `gdrive-upload`
* **Action:** Reads `$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS`, verifies that selected paths reside inside the synchronized tree, preserves the relative folder hierarchy, and uploads only the selected items directly to `gdrive_dev:Synced` via `rclone copy` / `copyto` without waiting for a full bisync pass.

#### 3. `Send to Phone via Bluetooth`
* **Trigger:** Select file(s) in Nautilus $\to$ **Scripts** $\to$ **Send to Phone via Bluetooth**.
* **Target:** `bluetooth-send`
* **Action:** Transmits selected files to your mobile phone via `blueman-sendto`.
* **Privacy & Configuration:** Zero personal information or MAC addresses are stored in the git repository. The target MAC address is resolved dynamically:
  1. `$BLUETOOTH_PHONE_MAC` environment variable.
  2. `~/.config/scripts/bluetooth_phone.mac` (single MAC string).
  3. `~/.config/scripts/bluetooth_phone.conf` (`PHONE_MAC=...`).
  4. Auto-discovery of a single paired phone via `bluetoothctl devices Paired`.
  * Can be configured in one command: `bluetooth-send --setup <MAC>`.



