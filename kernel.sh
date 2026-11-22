#!/usr/bin/env bash
# Prints the running kernel version without the distro suffix (6.8.0-45-generic -> 6.8.0).
# Installed as `kernel` in ~/.local/bin, so it works the same in bash, zsh and Nushell.

uname -r | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/'
