# Fish completion for keylight
complete -c keylight -s h -l help -d "Show help message"
complete -c keylight -s n -l next -d "Switch to next profile"
complete -c keylight -s c -l current -d "Show currently active profile"
complete -c keylight -s l -l list -d "List available profiles"
complete -c keylight -f -a "off night cyan white" -d "RGB profile"
