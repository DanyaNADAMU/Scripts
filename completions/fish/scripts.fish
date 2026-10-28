# Fish completion for scripts
# Unified manager for nada.mu utilities

# Subcommands
complete -c scripts -f -n "__fish_use_subcommand" -a "update" -d "Pull updates and sync utilities"
complete -c scripts -f -n "__fish_use_subcommand" -a "list" -d "List declared utilities and installation status"
complete -c scripts -f -n "__fish_use_subcommand" -a "prune" -d "Clean up removed or orphaned utilities"
complete -c scripts -f -n "__fish_use_subcommand" -a "clean" -d "Clean up temporary cache and files"
complete -c scripts -f -n "__fish_use_subcommand" -a "autoupdate" -d "Manage automated background updates"
complete -c scripts -f -n "__fish_use_subcommand" -a "uninstall" -d "Remove utilities, completions, and man pages"
complete -c scripts -f -n "__fish_use_subcommand" -a "help" -d "Display help information"

# Global options
complete -c scripts -s h -l help -d "Show help message"
complete -c scripts -s v -l version -d "Show version"
complete -c scripts -s y -l yes -d "Assume yes to all prompts"
complete -c scripts -l scope -x -a "user system" -d "Target scope (user space or system-wide)"
complete -c scripts -l category -x -a "all server desktop media" -d "Filter utilities by category"
complete -c scripts -l method -x -a "link copy" -d "Installation method (symlink or copy)"

# autoupdate subcommands
complete -c scripts -f -n "__fish_seen_subcommand_from autoupdate" -a "status" -d "Check status of auto-update mechanisms"
complete -c scripts -f -n "__fish_seen_subcommand_from autoupdate" -a "enable" -d "Enable auto-update mechanism"
complete -c scripts -f -n "__fish_seen_subcommand_from autoupdate" -a "disable" -d "Disable auto-update mechanism"

# autoupdate targets
complete -c scripts -f -n "__fish_seen_subcommand_from enable disable" -a "systemd" -d "Systemd timer"
complete -c scripts -f -n "__fish_seen_subcommand_from enable disable" -a "shell" -d "Interactive shell startup hook"
complete -c scripts -f -n "__fish_seen_subcommand_from enable disable" -a "cron" -d "Cron schedule"
complete -c scripts -f -n "__fish_seen_subcommand_from enable disable" -a "apt" -d "APT package manager hook"
complete -c scripts -f -n "__fish_seen_subcommand_from enable disable" -a "pacman" -d "Pacman / ALPM package manager hook"
complete -c scripts -f -n "__fish_seen_subcommand_from enable disable" -a "git" -d "Git post-merge hook"
complete -c scripts -f -n "__fish_seen_subcommand_from enable disable" -a "all" -d "All applicable mechanisms"

# uninstall targets
complete -c scripts -f -n "__fish_seen_subcommand_from uninstall" -a "media backup-seafile backup-seadrive keylight languagetool-portal setup-user"
