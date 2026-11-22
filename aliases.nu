
# --- NUSHELL Shell Aliases ---
#
# Commands that choose between installed tools are custom commands (`def --wrapped`, which
# passes any flags straight through). The choice is made when the command runs: an `alias`
# or `def` written inside an `if` block would only exist inside that block.
#
# kernel, showip and weather are small scripts in ~/.local/bin (shared with bash and zsh).

# Directory listings
def --wrapped ll [...rest] {
    if (which lsd | is-not-empty) {
        ^lsd -lahX --group-directories-first ...$rest
    } else if (which eza | is-not-empty) {
        ^eza --long --all --header --git --classify --sort=type ...$rest
    } else if (which exa | is-not-empty) {
        ^exa --long --all --header --git --classify --sort=type ...$rest
    } else {
        ^ls -la ...$rest
    }
}

def --wrapped tree [...rest] {
    if (which eza | is-not-empty) {
        ^eza -1 -F --tree ...$rest
    } else if (which exa | is-not-empty) {
        ^exa -1 -F --tree ...$rest
    } else {
        ^tree ...$rest
    }
}

# bat / batcat compatibility
def --wrapped bat [...rest] {
    if (which bat | is-not-empty) {
        ^bat ...$rest
    } else if (which batcat | is-not-empty) {
        ^batcat ...$rest
    } else {
        error make { msg: "bat is not installed" }
    }
}

# Moon phase
def moonphase [] {
    ^curl wttr.in/Moon
}

# Downloads
def --wrapped dl [...rest] {
    ^aria2c ...$rest
}
