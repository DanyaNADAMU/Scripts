# Fish completion for bluetooth-send
complete -c bluetooth-send -s h -l help -d "Show help message"
complete -c bluetooth-send -l setup -d "Configure target phone MAC address"
complete -c bluetooth-send -a "(__fish_complete_path)"
