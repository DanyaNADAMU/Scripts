# Fish completion for backup-seafile
complete -c backup-seafile -s h -l help -d "Show help message"
complete -c backup-seafile -s c -l config -r -d "Path to configuration file"
complete -c backup-seafile -l setup-timer -d "Install and enable resilient systemd timer"
complete -c backup-seafile -l remove-timer -d "Disable and remove the systemd timer"
complete -c backup-seafile -l status -d "Display timer status, prerequisites, and recent logs"
complete -c backup-seafile -l force -d "Force backup now, bypassing cooldown and lock checks"
complete -c backup-seafile -l dry-run -d "Perform trial run without writing changes to remote"
complete -c backup-seafile -l auto -d "Automated run mode used by systemd timer"
