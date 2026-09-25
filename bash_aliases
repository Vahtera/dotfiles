# --- BASH / ZSH Shell Aliases ---

if command -v eza &>/dev/null; then
    alias ls='eza -1 -F --long --git --classify --sort=type'
    alias ll='eza --long --all --header --git --classify --sort=type'
    alias tree='eza -1 -F --tree'
elif command -v exa &>/dev/null; then
    alias ls='exa -1 -F --long --git --classify --sort=type'
    alias ll='exa --long --all --header --git --classify --sort=type'
    alias tree='exa -1 -F --tree'
fi

if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
    alias bat='batcat'
fi

alias kernel="uname -r | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/'"
alias showip='ip -4 addr show scope global | grep inet | awk "{print \$2}" | cut -d"/" -f1 | paste -s -d, -'
alias weather='curl wttr.in/Tampere?M'
