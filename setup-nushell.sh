#!/usr/bin/env bash
###############################################################################
# Updates the managed Nushell configuration and sources it from config.nu / env.nu.
# Run by setup.sh, or on its own to update just Nushell: ~/.local/bin/setup-nushell.sh
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

if ! command -v nu &>/dev/null; then
    echo -e "${YELLOW}nushell is not installed; skipping the Nushell configuration.${RESET}"
    exit 0
fi

status=0
NUSHELL_CONFIG_DIR="$HOME/.config/nushell"
NUSHELL_USER="$NUSHELL_CONFIG_DIR/nushell-user"
NUSHELL_ENV="$NUSHELL_CONFIG_DIR/nushell-env"
echo -e "${CYAN}Updating $NUSHELL_CONFIG_DIR/config.nu...${RESET}"
mkdir -p "$NUSHELL_CONFIG_DIR"
touch "$NUSHELL_CONFIG_DIR/config.nu"
touch "$NUSHELL_CONFIG_DIR/env.nu"

if fetch_file "nushell-user" "$NUSHELL_USER"; then
    echo -e "  ${GREEN}✓ Updated $NUSHELL_USER${RESET}"
else
    status=1
fi

if fetch_file "nushell-env" "$NUSHELL_ENV"; then
    echo -e "  ${GREEN}✓ Updated $NUSHELL_ENV${RESET}"
else
    status=1
fi

if fetch_file "aliases.nu" "$NUSHELL_CONFIG_DIR/aliases.nu"; then
    echo -e "  ${GREEN}✓ Copied aliases.nu to $NUSHELL_CONFIG_DIR/aliases.nu${RESET}"
else
    status=1
fi

# Nushell has no [[ ]] or &&, so earlier versions of the setup wrote lines that
# cannot be parsed. Remove those, then use plain `source` lines.
for nu_file in config.nu env.nu; do
    if grep -qF '[[ -f "$HOME/.config/nushell/nushell-' "$NUSHELL_CONFIG_DIR/$nu_file"; then
        grep -vF '[[ -f "$HOME/.config/nushell/nushell-' "$NUSHELL_CONFIG_DIR/$nu_file" \
            > "$NUSHELL_CONFIG_DIR/$nu_file.tmp" || true
        cat "$NUSHELL_CONFIG_DIR/$nu_file.tmp" > "$NUSHELL_CONFIG_DIR/$nu_file"
        rm -f "$NUSHELL_CONFIG_DIR/$nu_file.tmp"
        echo -e "  ${YELLOW}Removed old bash-style source lines from $NUSHELL_CONFIG_DIR/$nu_file${RESET}"
    fi
done

ensure_source_line "$NUSHELL_CONFIG_DIR/config.nu" 'source ~/.config/nushell/nushell-user' "nushell-user"
ensure_source_line "$NUSHELL_CONFIG_DIR/env.nu" 'source ~/.config/nushell/nushell-env' "nushell-env"

exit "$status"
