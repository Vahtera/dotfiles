#!/usr/bin/env bash
###############################################################################
# 🚀 Dotfiles Master Bootstrap / Setup Script
# Repo: https://github.com/Vahtera/dotfiles
###############################################################################

set -e

# Colors
PURPLE='\033[0;35m'
CYAN='\033[1;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

echo -e "${CYAN}====================================================${RESET}"
echo -e "${PURPLE}   Setting up Dotfiles for user: ${YELLOW}$USER${RESET}"
echo -e "${CYAN}====================================================${RESET}\n"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

# Copy CLI tools to $HOME/.local/bin
echo -e "${CYAN}[1/4] Installing CLI tools to $LOCAL_BIN...${RESET}"
if [ -f "$SCRIPT_DIR/welcome_banner.sh" ]; then
    cp "$SCRIPT_DIR/welcome_banner.sh" "$LOCAL_BIN/welcome_banner.sh"
    chmod +x "$LOCAL_BIN/welcome_banner.sh"
    echo -e "  ${GREEN}✓ Installed welcome_banner.sh${RESET}"
fi

if [ -f "$SCRIPT_DIR/run_benchmark.sh" ]; then
    cp "$SCRIPT_DIR/run_benchmark.sh" "$LOCAL_BIN/run_benchmark.sh"
    chmod +x "$LOCAL_BIN/run_benchmark.sh"
    echo -e "  ${GREEN}✓ Installed run_benchmark.sh${RESET}"
fi

# Deploy .bash_aliases
echo -e "\n${CYAN}[2/4] Deploying .bash_aliases...${RESET}"
if [ -f "$SCRIPT_DIR/.bash_aliases" ]; then
    cp "$SCRIPT_DIR/.bash_aliases" "$HOME/.bash_aliases"
    echo -e "  ${GREEN}✓ Copied .bash_aliases to $HOME/.bash_aliases${RESET}"
fi

# Update .bashrc safely
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

# Run package installation script
echo -e "\n${CYAN}[4/4] Package Installation Check...${RESET}"
if [ -f "$SCRIPT_DIR/debian-apt.sh" ]; then
    chmod +x "$SCRIPT_DIR/debian-apt.sh"
    read -p "Would you like to run debian-apt.sh to update and install packages now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$SCRIPT_DIR/debian-apt.sh" "$@"
    else
        echo -e "  ${YELLOW}Skipped package installation. You can run ./debian-apt.sh manually later.${RESET}"
    fi
fi

echo -e "\n${GREEN}====================================================${RESET}"
echo -e "${GREEN}   ✨ Dotfiles setup complete! Restart terminal or run: source ~/.bashrc${RESET}"
echo -e "${GREEN}====================================================${RESET}"
