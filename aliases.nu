
# --- NUSHELL Shell Aliases ---
#
# ll, tree and bat are not defined here: setup-nushell.sh appends them below when it deploys
# this file, based on which tools are installed. (A Nushell alias cannot be conditional, and a
# custom command would hide the terminal from the tool, so bat, eza and lsd would lose their
# colors and paging.) Run ~/.local/bin/setup-nushell.sh again after installing one of them.
#
# kernel, showip and weather are small scripts in ~/.local/bin (shared with bash and zsh).

alias moonphase = curl wttr.in/Moon
alias dl = aria2c
