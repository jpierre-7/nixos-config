# Login shell - Environment setup and one-time initializations
if status is-login
    # Tool initializations
    starship init fish | source
end

# Interactive shell - Shell behavior and user interface
if status is-interactive
    fish_config theme choose catppuccin

    # Aliases
    alias ls="lsd"
    alias l='lsd -l'
    alias la='lsd -a'
    alias lla='lsd -la'
    alias lt='lsd --tree'

    # Abbreviations
    abbr -a l lsd
    abbr -a lt "lsd --tree"
    abbr -a lta "lsd --tree -a"
    abbr -a nv nvim
    abbr -a lg lazygit
    abbr -a qcd --position command --regex "q+" --function qcd
    abbr -a vg "ssh veggie.ooapi.com"

    set -g fish_key_bindings fish_vi_key_bindings

    # Interactive functions
    function run-ls-on-cd -v PWD
        set current_repository (git rev-parse --show-toplevel 2> /dev/null)
        if [ "$current_repository" ] && [ "$current_repository" != "$last_repository" ]
            onefetch
        end
        set -gx last_repository $current_repository
        command lsd -l
    end

    function fish_greeting
        fastfetch
    end
end
