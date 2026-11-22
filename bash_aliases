# --- BASH / ZSH Shell Aliases ---

if command -v lsd &>/dev/null; then
    alias ls='lsd -1X --group-directories-first'
    alias ll='lsd -lahX --group-directories-first'
elif command -v eza &>/dev/null; then
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

if command -v pom &>/dev/null; then
    alias moonphase='curl wttr.in/Moon'
fi

if command -v aria2c &>/dev/null; then
    alias dl='aria2c'
fi

# kernel, showip and weather are scripts in ~/.local/bin (kernel.sh, showip.sh, weather.sh),
# shared with Nushell, so they are not defined here.
