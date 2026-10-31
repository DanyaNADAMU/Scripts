# scripts

Centralized repository of automation utilities, server administration tools, workstation workflows, and cryptographic media attestation scripts for the `nada.mu` ecosystem.

All commits are cryptographically signed with SSH Ed25519 (`git@nada.mu`) and anchored into the Bitcoin blockchain via OpenTimestamps (`git-ots`).

---

## Directory Structure & Architecture

```text
scripts/
├── .github/workflows/       # CI & OpenTimestamps blockchain anchoring
├── .githooks/               # Git post-commit & pre-push hooks
├── .allowed_signers         # Canonical trusted SSH commit signers
├── SECURITY.md              # Security policy & disclosure guidelines
├── manifest.txt             # Single source of truth for all declared utilities
├── scripts                  # Unified CLI manager (install, update, list, uninstall)
├── install.sh               # Bootstrap launcher (local & curl | bash)
├── README.md                # Repository index & documentation
│
├── docs/                    # Documentation & man pages
│   ├── STANDARDS.md         # Engineering & documentation standards
│   └── man/man1/            # Troff Linux man pages (media.1, setup-user.1, keylight.1, scripts.1)
│
├── completions/             # Shell tab-completions
│   ├── bash/                # Bash completions
│   └── zsh/                 # Zsh completions
│
├── server/                  # Server-side administration & provisioning
│   ├── setup_user.sh        # Linux user provisioning with rootless Podman
│   ├── backup_seafile.sh    # Resilient encrypted Seafile to Google Drive backup
│   └── languagetool_portal.py # Self-service token portal for LanguageTool & Authentik
│
├── desktop/                 # Workstation & desktop environment scripts
│   ├── backup_seadrive.sh   # Automated encrypted SeaDrive to Google Drive backup
│   ├── bisync_synced.sh     # Resilient bidirectional Google Drive sync with Btrfs snapshots
│   ├── gdrive_upload.sh     # Rapid direct file/folder upload to Google Drive
│   ├── bluetooth_send.sh    # Dynamic Bluetooth transfer to paired phone
│   ├── keylight.py          # High-performance keyboard RGB backlight profile switcher
│   └── compat/              # Integration bridges & upstream compatibility shims
│       ├── nautilus_kdeconnect.sh # URL & path translator for GNOME Nautilus
│       └── sshfs_shim.sh    # PATH shim stripping deprecated DSA from sshfs
│
└── media/                   # Cryptographic media & attestation tools
    └── media.py             # C2PA manifest signing, invisible watermarking & asset pipeline
```

---

## Quick Start & Installation

### Option 1: Standalone Install via `curl | bash` (No git clone needed)
Ideal for fresh servers or remote workstations. Installs all utilities automatically without interactive prompts:

```bash
curl -fsSL https://raw.githubusercontent.com/DanyaNADAMU/Scripts/main/install.sh | bash
```

**Zero-Prompt Defaults:**
* **Scope:** Automatically targets user space (`~/.local/bin`, no sudo required). If executed by `root`, automatically targets system space (`/usr/local/bin`).
* **Category:** Synchronizes `all` declared utilities.
* **Displays:** Prints a clean summary table of installed utilities, categories, and descriptions.

#### Customizing Installation:
```bash
# Install server utilities only to ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/DanyaNADAMU/Scripts/main/install.sh | bash -s -- --category server

# Force system-wide installation
curl -fsSL https://raw.githubusercontent.com/DanyaNADAMU/Scripts/main/install.sh | sudo bash -s -- --scope system
```

---

### Option 2: Developer Workflow (Cloned Repository)
For developing and contributing to scripts:

```bash
# 1. Clone into standard projects directory
git clone https://github.com/DanyaNADAMU/Scripts.git ~/projects/scripts
cd ~/projects/scripts

# 2. Link utilities into ~/.local/bin (symlinks allow live edits)
./scripts update
```

Ensure `~/.local/bin` is in your `$PATH` (in `~/.zshrc` or `~/.bashrc`):
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

### Option 3: Arch Linux & CachyOS First-Class Integration

For Arch Linux, CachyOS, and other ALPM-based systems, `scripts` provides native first-class integration:

#### A. AUR Helper (Paru / Yay)
```bash
paru -S scripts-git
# or
yay -S scripts-git
```

#### B. Intelligent Bootstrap Installer (`install.sh`)
When executed on Arch Linux or CachyOS, `install.sh` automatically detects the environment:
```bash
# Interactive mode: prompts to choose native makepkg or user-space symlinks
./install.sh

# Direct native build & install
./install.sh --native

# Remote one-liner building native pacman package directly
curl -fsSL https://raw.githubusercontent.com/DanyaNADAMU/Scripts/main/install.sh | bash -s -- --native
```

#### C. Local Package Building (`scripts pkgbuild` / `makepkg`)
To build and install the native `.pkg.tar.zst` directly from your local working tree without re-cloning from GitHub:
```bash
cd ~/projects/scripts
scripts pkgbuild -i
# or standard makepkg
makepkg -si
```

This builds and installs `scripts-git`, placing binaries in `/usr/bin`, registering man pages and shell completions (Bash, Zsh, Fish), and configuring the ALPM post-transaction update hook (`/usr/share/libalpm/hooks/99scripts.hook`).

---

## System Diagnostics: `scripts doctor`

Run the built-in diagnostic tool to inspect environment health, core runtime requirements (`bash`, `git`, `systemd`, `uv`), and optional tool dependencies:

```bash
scripts doctor
```

On Arch Linux and CachyOS, `scripts doctor` identifies missing optional tools and outputs the exact `pacman` command to install them. Use `--fix` to run remediation automatically:

```bash
scripts doctor --fix
```

---

## Management via the `scripts` Command

Once installed, the `scripts` manager is available anywhere in your terminal:

```bash
scripts update               # Pull upstream updates and sync all utilities (default: all)
scripts list                 # View all declared utilities and installation status
scripts doctor               # Run comprehensive system and dependency diagnostics
scripts pkgbuild             # Build native Arch/CachyOS package from local tree
scripts autoupdate status    # Check status of automated update mechanisms across the system
scripts autoupdate enable    # Enable auto-update (systemd, shell, cron, apt, pacman, git, all)
scripts uninstall            # Cleanly remove all utilities, man pages, and completions
scripts --help               # View command options and help
```

### Transparent Updates & Scope Protection
* **Automatic Synchronization:** `scripts update` verifies SHA-256 digests, pulls upstream changes (when inside a git clone), updates binaries, installs completions and man pages, and cleans up deprecated utilities. (Aliases `sync` and `install` are supported).
* **Scope Protection:** If you run `scripts update` and an existing installation is detected with mismatched privileges, `scripts` safely prompts you to choose the desired action rather than creating accidental duplicates.
* **Automated Updates (Zero-Friction):** Stay effortlessly up to date across multiple environments:
  * **Systemd Timers:** Daily scheduled updates with `Persistent=true` and randomized delay (`scripts autoupdate enable systemd`). Works in user space without root!
  * **Interactive Shell Hook:** Silent background synchronization on terminal startup with 24-hour rate limit (`scripts autoupdate enable shell`). Supports Bash, Zsh, and Fish!
  * **Cron Jobs:** Scheduled daily update via user crontab or `/etc/cron.daily` (`scripts autoupdate enable cron`).
  * **APT Hook:** Silent, non-blocking background hook in `/etc/apt/apt.conf.d/99scripts` for Debian/Ubuntu systems (24h cooldown, detached execution).
  * **Pacman Hook:** Silent, non-blocking ALPM background hook in `/etc/pacman.d/hooks/99scripts.hook` for Arch Linux & CachyOS (24h cooldown, detached execution).
  * **Git Post-Merge Hook:** Automatically re-syncs utilities upon `git pull` in cloned repositories.

---

## Documentation & Manual Pages

Every utility provides multi-level documentation:
1. **Interactive CLI Help:** Run `<command> --help` or `<command> -h` for quick flags and usage.
2. **Linux Man Pages:** Installed automatically into `~/.local/share/man/man1/` or `/usr/local/share/man/man1/`:
   ```bash
   man setup-user
   man scripts
   ```
3. **Repository Specifications:** See [`docs/STANDARDS.md`](docs/STANDARDS.md) for detailed coding rules.

---

## Shell Completions (Tab Key)

Tab completion for command names works out-of-the-box in all shells (`sh`, `bash`, `zsh`, `fish`) because binaries live in `$PATH`.

Rich argument and flag completions (`setup-user --<Tab>`, `scripts <Tab>`) are installed automatically for:
* **Bash:** Installed to `~/.local/share/bash-completion/completions/` (or `/usr/share/bash-completion/completions/`)
* **Zsh:** Installed to `~/.local/share/zsh/site-functions/` (or `/usr/local/share/zsh/site-functions/`)
* **Fish:** Installed to `~/.config/fish/completions/` (or `/usr/share/fish/vendor_completions.d/`)

---

## Script Catalog

| Command | Source Path | Category | Description | Runtime / Dependencies |
| :--- | :--- | :--- | :--- | :--- |
| `scripts` | `scripts` | **Manager** | CLI package manager for the scripts ecosystem. | Bash |
| `setup-user` | `server/setup_user.sh` | **Server** | *(Deprecated)* Provisions a new Linux user with Zsh, SSH keys, lingering, and rootless Podman. | Bash, `systemd`, `podman` |
| `backup-seafile` | `server/backup_seafile.sh` | **Server** | Automated encrypted incremental backup from Seafile (WebDAV/FUSE) to Google Drive. | Bash, `rclone`, `systemd` |
| `backup-seadrive` | `desktop/backup_seadrive.sh` | **Desktop** | Automated encrypted incremental backup from SeaDrive to Google Drive via Rclone. | Bash, `rclone`, `systemd` |
| `keylight` | `desktop/keylight.py` | **Desktop** | Ultra-low latency keyboard RGB profile switcher via OpenRGB SDK socket. | Python $\ge$ 3.10, `uv`, OpenRGB |
| `languagetool-portal` | `server/languagetool_portal.py` | **Server** | Self-service token portal for LanguageTool with Authentik forward auth. | Python $\ge$ 3.10 (standard library only) |
| `media` | `media/media.py` | **Media** | Unified media lifecycle: C2PA attestation, DWT steganography, Bitcoin timestamps & asset packaging. | Python $\ge$ 3.11, `uv` |
| `scan-reality` | `server/scan_reality.py` | **Server** | High-performance async TLS 1.3 & HTTP/2 camouflage scanner for XTLS Reality. | Python $\ge$ 3.11, `uv` |
| `nautilus-kdeconnect` | `desktop/compat/nautilus_kdeconnect.sh` | **Desktop** | Compatibility bridge translating `kdeconnect://` URLs and `kioexec` cache paths for Nautilus. | Bash, `nautilus` |
| `sshfs` | `desktop/compat/sshfs_shim.sh` | **Desktop** | Compatibility shim stripping deprecated DSA (`ssh-dss`) and enforcing keepalive timeouts for `sshfs`. | Bash, `sshfs` |
| `bisync-synced` | `desktop/bisync_synced.sh` | **Desktop** | Bidirectional Google Drive sync with Btrfs snapshot protection and notifications. | Bash, `rclone`, `btrfs-progs` |
| `gdrive-upload` | `desktop/gdrive_upload.sh` | **Desktop** | Quick upload of files and folders directly to Google Drive via Rclone. | Bash, `rclone` |
| `bluetooth-send` | `desktop/bluetooth_send.sh` | **Desktop** | Wireless file transfer to paired mobile phone via Bluetooth. | Bash, `blueman-sendto` |

