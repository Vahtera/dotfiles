#!/usr/bin/env bash
###############################################################################
# Shared helpers for setup.sh and the setup-<shell>.sh scripts. Source this file.
#
# Callers set SCRIPT_DIR to the repository directory when running from a local
# clone; leave it empty to download files from GitHub instead.
###############################################################################

# Colors
PURPLE='\033[0;35m'
CYAN='\033[1;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/Vahtera/dotfiles/main}"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config}"

# fetch_file NAME DEST - copy NAME from the local clone, or download it from GitHub.
# Returns non-zero (and leaves DEST untouched) when the file could not be fetched.
fetch_file() {
    local filename="$1"
    local dest="$2"

    if [ -n "${SCRIPT_DIR:-}" ] && [ -f "$SCRIPT_DIR/$filename" ]; then
        cp "$SCRIPT_DIR/$filename" "$dest"
        return
    fi

    local tmp rc=0
    tmp="$(mktemp)" || return 1
    if command -v curl &>/dev/null; then
        curl -fsSL "$REPO_RAW_URL/$filename" -o "$tmp" || rc=$?
    elif command -v wget &>/dev/null; then
        wget -qO "$tmp" "$REPO_RAW_URL/$filename" || rc=$?
    else
        echo -e "${YELLOW}❌ Error: Could not locate $filename locally nor via curl/wget.${RESET}"
        rc=1
    fi

    if [ "$rc" -eq 0 ]; then
        cat "$tmp" > "$dest" || rc=$?
    else
        echo -e "${YELLOW}❌ Could not download $filename (exit $rc).${RESET}"
    fi
    rm -f "$tmp"
    return "$rc"
}

# ensure_source_line FILE LINE NAME - append LINE to FILE unless it is already there.
ensure_source_line() {
    local file="$1" line="$2" name="$3"
    if ! grep -qF -- "$line" "$file"; then
        printf '\n%s\n' "$line" >> "$file"
        echo -e "  ${GREEN}✓ Added the $name source line to $file${RESET}"
    else
        echo -e "  ${YELLOW}The $name source line already exists in $file.${RESET}"
    fi
}

# deploy_bash_aliases - bash and zsh share ~/.bash_aliases.
deploy_bash_aliases() {
    if fetch_file "bash_aliases" "$HOME/.bash_aliases"; then
        echo -e "  ${GREEN}✓ Copied .bash_aliases to $HOME/.bash_aliases${RESET}"
    else
        return 1
    fi
}
