# Fish completion for bisync-synced
complete -c bisync-synced -s h -l help -d "Show help message"
complete -c bisync-synced -l resync -d "Perform initial resync baseline pass"
complete -c bisync-synced -l dry-run -d "Perform trial run without transferring data"
complete -c bisync-synced -l status -d "Display lock state and recent log entries"
