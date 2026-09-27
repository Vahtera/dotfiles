#!/usr/bin/env bash
###############################################################################
# 🚀 Dotfiles Master Bootstrap / Setup Script (v2)
# Repo: https://github.com/Vahtera/dotfiles
###############################################################################

set -e

# Colors
PURPLE='\033[0;35m'
CYAN='\033[1;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

REPO_RAW_URL="https://raw.githubusercontent.com/Vahtera/dotfiles/main"

echo -e "${CYAN}====================================================${RESET}"
echo -e "${PURPLE}   Setting up Dotfiles for user: ${YELLOW}$USER${RESET}"
echo -e "${CYAN}====================================================${RESET}\n"

# Determine directory if running from a local clone
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )"

LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

# Helper function to fetch files locally or from GitHub raw URL
fetch_file() {
    local filename="$1"
    local dest="$2"

    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$filename" ]; then
        cp "$SCRIPT_DIR/$filename" "$dest"
        return 0
    elif command -v curl &>/dev/null; then
        curl -sSL "$REPO_RAW_URL/$filename" -o "$dest"
        return 0
    elif command -v wget &>/dev/null; then
        wget -qO "$dest" "$REPO_RAW_URL/$filename"
        return 0
    else
        echo -e "${YELLOW}❌ Error: Could not locate $filename locally nor via curl/wget.${RESET}"
        return 1
    fi
}

# 1. Install CLI tools to $HOME/.local/bin
echo -e "${CYAN}[1/4] Installing CLI tools to $LOCAL_BIN...${RESET}"

if fetch_file "welcome_banner.sh" "$LOCAL_BIN/welcome_banner.sh"; then
    chmod +x "$LOCAL_BIN/welcome_banner.sh"
    echo -e "  ${GREEN}✓ Installed welcome_banner.sh${RESET}"
fi

if fetch_file "run_benchmark.sh" "$LOCAL_BIN/run_benchmark.sh"; then
    chmod +x "$LOCAL_BIN/run_benchmark.sh"
    echo -e "  ${GREEN}✓ Installed run_benchmark.sh${RESET}"
fi

# 2. Deploy .bash_aliases
echo -e "\n${CYAN}[2/4] Deploying .bash_aliases...${RESET}"
if fetch_file ".bash_aliases" "$HOME/.bash_aliases"; then
    echo -e "  ${GREEN}✓ Copied .bash_aliases to $HOME/.bash_aliases${RESET}"
fi

# 3. Update .bashrc safely
echo -e "\n${CYAN}[3/4] Updating $HOME/.bashrc...${RESET}"
BASHRC="$HOME/.bashrc"
touch "$BASHRC"

MARKER="# --- Vahtera Dotfiles Configuration ---"

if grep -qF "$MARKER" "$BASHRC"; then
    echo -e "  ${YELLOW}⚠ Dotfiles configuration already exists in $BASHRC (skipping duplicate append).${RESET}"
else
    cat << 'EOF' >> "$BASHRC"

# --- Vahtera Dotfiles Configuration ---
# Ensure local bin is in PATH dynamically for active user
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$PATH:$HOME/.local/bin"
fi

# Initialize thefuck if installed
if command -v thefuck &>/dev/null; then
    eval "$(thefuck --alias)"
fi

# Initialize Homebrew if installed
if [ -d "/home/linuxbrew/.linuxbrew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Run Welcome Banner on terminal launch
if [ -x "$HOME/.local/bin/welcome_banner.sh" ] && [[ $- == *i* ]]; then
    clear && "$HOME/.local/bin/welcome_banner.sh"
fi
# --------------------------------------
EOF
    echo -e "  ${GREEN}✓ Appended custom setup block to $BASHRC${RESET}"
fi

# 4. Run package installation script
echo -e "\n${CYAN}[4/4] Package Installation Check...${RESET}"

TEMP_APT_SCRIPT=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/debian-apt.sh" ]; then
    DEBIAN_APT_EXEC="$SCRIPT_DIR/debian-apt.sh"
else
    TEMP_APT_SCRIPT="$(mktemp /tmp/debian-apt.XXXXXX.sh)"
    if fetch_file "debian-apt.sh" "$TEMP_APT_SCRIPT"; then
        chmod +x "$TEMP_APT_SCRIPT"
        DEBIAN_APT_EXEC="$TEMP_APT_SCRIPT"
    else
        DEBIAN_APT_EXEC=""
    fi
fi

if [ -n "$DEBIAN_APT_EXEC" ] && [ -x "$DEBIAN_APT_EXEC" ]; then
    # Prompt user safely, attaching stdin to /dev/tty if stdin is piped
    PROMPT_CMD="read -p 'Would you like to run debian-apt.sh to update and install packages now? (y/N) ' -n 1 -r REPLY"
    if [ -c /dev/tty ]; then
        eval "$PROMPT_CMD < /dev/tty" || REPLY="N"
    else
        eval "$PROMPT_CMD" || REPLY="N"
    fi
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$DEBIAN_APT_EXEC" "$@"
    else
        echo -e "  ${YELLOW}Skipped package installation. You can run debian-apt.sh manually later.${RESET}"
    fi
fi

# Cleanup temp file if created
if [ -n "$TEMP_APT_SCRIPT" ] && [ -f "$TEMP_APT_SCRIPT" ]; then
    rm -f "$TEMP_APT_SCRIPT"
fi

echo -e "\n${GREEN}====================================================${RESET}"
echo -e "${GREEN}   ✨ Dotfiles setup complete! Restart terminal or run: source ~/.bashrc${RESET}"
echo -e "${GREEN}====================================================${RESET}"
