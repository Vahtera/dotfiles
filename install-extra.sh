#!/bin/bash

# Add one line per app: binary-name::install command
# Use single quotes around each entry so nothing is expanded until install time.
# curl uses -f so an HTTP error fails the install instead of piping an error page into a shell.
apps=(
    'croc::curl -fsSL https://getcroc.com | bash'
    'spf::bash -c "$(curl -fsSLo- https://superfile.dev/install.sh || echo exit 1)"'
    'concord::curl --proto =https --tlsv1.2 -LsSf https://github.com/chojs23/concord/releases/latest/download/concord-installer.sh | sh'
    'oh-my-posh::curl -fsSL https://ohmyposh.dev/install.sh | bash -s'
)

# Installers put binaries in ~/.local/bin, which is not always on PATH yet (fresh systems).
export PATH="$PATH:$HOME/.local/bin"

failed=()
for entry in "${apps[@]}"; do
    name="${entry%%::*}"   # everything before the first ::
    cmd="${entry#*::}"     # everything after it

    if command -v "$name" >/dev/null 2>&1; then
        echo "$name already installed, skipping."
        continue
    fi

    echo "Installing $name..."
    if bash -o pipefail -c "$cmd"; then
        if ! command -v "$name" >/dev/null 2>&1; then
            echo "Note: $name is not on PATH yet; open a new shell, or check where its installer put it."
        fi
    else
        echo "Failed to install $name."
        failed+=("$name")
    fi
done

if [ ${#failed[@]} -gt 0 ]; then
    echo "Failed: ${failed[*]}"
    exit 1
fi