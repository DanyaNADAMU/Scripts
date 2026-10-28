# Fish completion for backup-seadrive
complete -c backup-seadrive -s h -l help -d "Show help message"
complete -c backup-seadrive -l setup-timer -d "Install and enable resilient systemd user timer"
complete -c backup-seadrive -l remove-timer -d "Disable and remove the systemd user timer"
complete -c backup-seadrive -l status -d "Display timer status, prerequisites, and recent logs"
complete -c backup-seadrive -l force -d "Force backup now, bypassing cooldown and lock checks"
complete -c backup-seadrive -l dry-run -d "Perform trial run without writing changes to remote"
complete -c backup-seadrive -l auto -d "Automated run mode used by systemd timer"
