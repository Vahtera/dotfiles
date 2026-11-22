#!/usr/bin/env bash
###############################################################################
# Updates the managed zsh configuration and sources it from ~/.zshrc.
# Run by setup.sh, or on its own to update just zsh: ~/.local/bin/setup-zsh.sh
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

if ! command -v zsh &>/dev/null; then
    echo -e "${YELLOW}zsh is not installed; skipping the zsh configuration.${RESET}"
    exit 0
fi

status=0
echo -e "${CYAN}Updating $HOME/.zshrc...${RESET}"
ZSHRC="$HOME/.zshrc"
ZSH_CONFIG_DIR="$HOME/.config/shells/zsh"
ZSHRC_USER="$ZSH_CONFIG_DIR/zshrc-user"
mkdir -p "$ZSH_CONFIG_DIR"
touch "$ZSHRC"

if fetch_file "zshrc-user" "$ZSHRC_USER"; then
    echo -e "  ${GREEN}✓ Updated $ZSHRC_USER${RESET}"
else
    status=1
fi

ensure_source_line "$ZSHRC" \
    '[[ -f "$HOME/.config/shells/zsh/zshrc-user" ]] && source "$HOME/.config/shells/zsh/zshrc-user"' \
    "zshrc-user"

echo -e "\n${CYAN}Deploying .bash_aliases...${RESET}"
deploy_bash_aliases || status=1

exit "$status"
