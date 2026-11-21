
# --- NUSHELL Shell Aliases ---

# Directory listings
if (which lsd | is-not-empty) {
    alias ll = lsd -lahX --group-directories-first
} else if (which eza | is-not-empty) {
    alias ll = eza --long --all --header --git --classify --sort=type
    alias tree = eza -1 -F --tree
} else if (which exa | is-not-empty) {
    alias ll = exa --long --all --header --git --classify --sort=type
    alias tree = exa -1 -F --tree
}

# bat / batcat compatibility
if (which batcat | is-not-empty) and (which bat | is-empty) {
    alias bat = batcat
}

# Moon phase
if (which pom | is-not-empty) {
    alias moonphase = ^curl wttr.in/Moon
}

# Downloads
if (which aria2c | is-not-empty) {
    alias dl = aria2c
}

# System information
alias kernel = (uname -r | str replace --regex '(-.*$)' '')

alias showip = (
    ip -4 addr show scope global
    | lines
    | parse --regex 'inet (?<ip>[\d.]+)'
    | get ip
    | str join ','
)

# Weather
alias weather = (
    ^sh -c 'CITY=$(curl -fsS --max-time 3 "http://ip-api.com/line/?fields=city" 2>/dev/null) && curl "wttr.in/${CITY// /+}?M"'
)
