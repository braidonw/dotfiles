if status is-interactive
# Commands to run in interactive sessions can go here
    tv init fish | source
end

set -U fish_greeting

set -gx PATH \
            $HOME/.cargo/bin \
            /opt/homebrew/bin \
            /opt/homebrew/sbin \
            /opt/homebrew/opt/curl/bin \
            /usr/local/go/bin \
            $HOME/.local/bin \
            $HOME/go/bin \
            $PATH
set -gx EDITOR nvim

# Key bindings
bind \e\[1\;5C forward-word
bind \e\[1\;5D backward-word
bind \e\[1\;3C forward-word
bind \e\[1\;3D backward-word
bind \e\[3~ delete-char
bind \e\[3\;3~ delete-word
bind \e\[H beginning-of-line
bind \e\[F end-of-line

# Starship prompt initialization
starship init fish | source

# Aliases
alias vim nvim
alias j just
alias jbr "just bash-run"
alias ls "eza --color=always"
alias l "eza --color=always -lhA"
alias ll "eza --color=always -lh"
alias lg lazygit
alias ld lazydocker
alias cc claude

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init2.fish 2>/dev/null || :
