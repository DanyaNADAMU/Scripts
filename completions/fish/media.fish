# Fish completion for media
# C2PA attestation, steganography, and OpenTimestamps pipeline

complete -c media -f -n "__fish_use_subcommand" -a "init" -d "Initialize directory structure for an asset version"
complete -c media -f -n "__fish_use_subcommand" -a "build" -d "Build, sign, and render multi-scale dist assets from master"
complete -c media -f -n "__fish_use_subcommand" -a "audit" -d "Run full non-blocking integrity and proof audit"
complete -c media -f -n "__fish_use_subcommand" -a "list" -d "List managed assets, versions, and latest symlinks"
complete -c media -f -n "__fish_use_subcommand" -a "upgrade" -d "Recursively upgrade OpenTimestamps proofs in Bitcoin"
complete -c media -f -n "__fish_use_subcommand" -a "sign" -d "Sign an individual image with C2PA and invisible watermark"
complete -c media -f -n "__fish_use_subcommand" -a "verify" -d "Inspect and verify C2PA, watermarks & OpenTimestamps"
complete -c media -f -n "__fish_use_subcommand" -a "stamp" -d "Anchor any file in Bitcoin blockchain via OpenTimestamps"
complete -c media -f -n "__fish_use_subcommand" -a "timer" -d "Manage background systemd timer for OpenTimestamps upgrades"
complete -c media -f -n "__fish_use_subcommand" -a "keys" -d "Manage C2PA signing keys and Bitwarden integration"

complete -c media -s h -l help -d "Show help message"
complete -c media -s v -l version -d "Show version"
