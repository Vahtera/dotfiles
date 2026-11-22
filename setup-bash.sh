#!/usr/bin/env bash
###############################################################################
# Updates the managed Bash configuration and sources it from ~/.bashrc.
# Run by setup.sh, or on its own to update just Bash: ~/.local/bin/setup-bash.sh
###############################################################################

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -r "$SCRIPT_DIR/setup-common.sh" ]]; then
    source "$SCRIPT_DIR/setup-common.sh"
elif [[ -r "$HOME/.local/bin/setup-common.sh" ]]; then
    source "$HOME/.local/bin/setup-common.sh"
else
    echo "setup-common.sh not found next to this script or in ~/.local/bin; run setup.sh first." >&2
    exit 1
fi

status=0
echo -e "${CYAN}Updating $HOME/.bashrc...${RESET}"
BASHRC="$HOME/.bashrc"
BASH_CONFIG_DIR="$HOME/.config/shells/bash"
BASHRC_USER="$BASH_CONFIG_DIR/bashrc-user"
mkdir -p "$BASH_CONFIG_DIR"
touch "$BASHRC"

# Install ble.sh if it is not already installed
install_blesh() {
    # lib/ is checked too, so an older install that only copied ble.sh gets repaired
    if [ -f "$HOME/.local/share/blesh/ble.sh" ] && [ -d "$HOME/.local/share/blesh/lib" ]; then
        return 0
    fi
    command -v xz >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 \
        || { echo "xz and tar are required for ble.sh" >&2; return 1; }
    local tmp rc=0; tmp="$(mktemp -d)" || return 1
    curl -fsSL -o "$tmp/ble.tar.xz" \
        https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz \
        && tar xJf "$tmp/ble.tar.xz" -C "$tmp" \
        && bash "$tmp/ble-nightly/ble.sh" --install "$HOME/.local/share" || rc=1
    rm -rf "$tmp"; return $rc
}
install_blesh || echo -e "  ${YELLOW}ble.sh installation failed; continuing.${RESET}"

if fetch_file "bashrc-user" "$BASHRC_USER"; then
    echo -e "  ${GREEN}✓ Updated $BASHRC_USER${RESET}"
else
    status=1
fi

ensure_source_line "$BASHRC" \
    '[[ -f "$HOME/.config/shells/bash/bashrc-user" ]] && source "$HOME/.config/shells/bash/bashrc-user"' \
    "bashrc-user"

echo -e "\n${CYAN}Deploying .bash_aliases...${RESET}"
deploy_bash_aliases || status=1

exit "$status"
