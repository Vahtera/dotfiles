#!/bin/bash

# Add one line per app: binary-name::install command
# Use single quotes around each entry so nothing is expanded until install time.
apps=(
    'croc::curl https://getcroc.com | bash'
    'spf::bash -c "$(curl -sLo- https://superfile.dev/install.sh)"'
    'concord::curl --proto =https --tlsv1.2 -LsSf https://github.com/chojs23/concord/releases/latest/download/concord-installer.sh | sh'
    'oh-my-posh::curl -s https://ohmyposh.dev/install.sh | bash -s'
)

failed=()
for entry in "${apps[@]}"; do
    name="${entry%%::*}"   # everything before the first ::
    cmd="${entry#*::}"     # everything after it

    if command -v "$name" >/dev/null 2>&1; then
        echo "$name already installed, skipping."
        continue
    fi

    echo "Installing $name..."
    if ! bash -o pipefail -c "$cmd"; then
        echo "Failed to install $name."
        failed+=("$name")
    fi
done

if [ ${#failed[@]} -gt 0 ]; then
    echo "Failed: ${failed[*]}"
    exit 1
fi