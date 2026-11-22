#!/usr/bin/env bash
# Prints this machine's global IPv4 addresses, comma-separated.
# Installed as `showip` in ~/.local/bin, so it works the same in bash, zsh and Nushell.

if ! command -v ip >/dev/null 2>&1; then
    echo "showip: the 'ip' command is not available on this system." >&2
    exit 1
fi

ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | paste -s -d, -
