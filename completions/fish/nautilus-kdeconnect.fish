# Fish completion for nautilus-kdeconnect
complete -c nautilus-kdeconnect -s h -l help -d "Show help message"
complete -c nautilus-kdeconnect -s r -l reset -d "Emergency reset/remount of hanging or zombie FUSE mounts"
complete -c nautilus-kdeconnect -a "(__fish_complete_directories)"
