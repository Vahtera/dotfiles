#!/usr/bin/env bash
################################################################
### 📜 Debian / Ubuntu APT Package Install & Update Script
################################################################
### Installs listed packages on Debian-based systems via apt-get
### Handles package alternatives (e.g., eza/exa, fastfetch/neofetch)
################################################################

PURPLE='\033[0;35m'
YELLOW='\033[0;93m'
CYAN_B='\033[1;96m'
LIGHT='\x1b[2m'
RESET='\033[0m'

PROMPT_TIMEOUT=15

if [[ $* == *"--auto-yes"* ]]; then
    PROMPT_TIMEOUT=0
    REPLY='Y'
fi

echo -e "${PURPLE}Starting Debian/Ubuntu package install & update script${RESET}"
echo -e "${YELLOW}Before proceeding, ensure you are happy with the packages listed in ${0##*/}${RESET}\n"

if [ "$EUID" -ne 0 ]; then
    echo -e "${PURPLE}Elevated permissions are required to install packages.${RESET}"
    echo -e "${CYAN_B}Please enter your password...${RESET}"
    sudo -v
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Exiting, as sudo authentication failed.${RESET}"
        exit 1
    fi
fi

if ! command -v apt &>/dev/null; then
    echo -e "${YELLOW}apt package manager non-existent on this system. Exiting.${RESET}"
    exit 1
fi

install_alternative() {
    local primary="$1"
    local fallback="$2"
    
    if command -v "$primary" &>/dev/null || command -v "$fallback" &>/dev/null; then
        echo -e "${YELLOW}[Skipping]${LIGHT} Either $primary or $fallback is already installed.${RESET}"
        return 0
    fi

    if apt-cache show "$primary" &>/dev/null 2>&1; then
        echo -e "${PURPLE}[Installing]${LIGHT} Installing primary package: $primary...${RESET}"
        sudo apt install -y "$primary"
    elif apt-cache show "$fallback" &>/dev/null 2>&1; then
        echo -e "${PURPLE}[Installing]${LIGHT} Primary package '$primary' not found. Installing fallback: $fallback...${RESET}"
        sudo apt install -y "$fallback"
    else
        echo -e "${YELLOW}[Warning] Neither $primary nor $fallback could be located in apt repositories.${RESET}"
    fi
}

debian_apps=(
    'git' 'neovim' 'ranger' 'tmux' 'wget' 'zsh' 'pipx' 'gh' 'lynx' 'elinks'
    'aria2' 'bat' 'broot' 'ctags' 'diff-so-fancy' 'duf' 'fzf' 'hyperfine' 
    'just' 'jq' 'most' 'procs' 'ripgrep' 'scrot' 'sd' 'thefuck' 'tealdeer' 
    'tree' 'tokei' 'trash-cli' 'xsel' 'zoxide' 'qalc'
    'golang' 'nodejs' 'npm' 'python3-full'
    'clamav' 'cryptsetup' 'gnupg' 'git-crypt' 'lynis' 'openssl' 'rkhunter'
    'btop' 'bmon' 'ctop' 'gping' 'glances' 'goaccess' 'speedtest-cli' 'wavemon' 'sysbench'
    'cowsay' 'figlet' 'lolcat' 'nudoku'
)

python_apps=( 'epy-reader' 'lazygit' 'tuir' )

# Update package database
echo -e "${CYAN_B}Would you like to update package database? (y/N)${RESET}"
read -t $PROMPT_TIMEOUT -n 1 -r REPLY
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${PURPLE}Updating database...${RESET}"
    sudo apt update
fi

# Upgrade existing packages
echo -e "${CYAN_B}Would you like to upgrade currently installed packages? (y/N)${RESET}"
read -t $PROMPT_TIMEOUT -n 1 -r REPLY
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${PURPLE}Upgrading installed packages...${RESET}"
    sudo apt upgrade -y
fi

# Install Debian APT Applications
echo -e "${CYAN_B}Would you like to install listed apps? (y/N)${RESET}"
read -t $PROMPT_TIMEOUT -n 1 -r REPLY
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${PURPLE}Starting APT installation...${RESET}"
    
    echo -e "${PURPLE}Checking package alternatives...${RESET}"
    install_alternative "eza" "exa"
    install_alternative "fastfetch" "neofetch"

    for app in "${debian_apps[@]}"; do
        if command -v "$app" &>/dev/null; then
            echo -e "${YELLOW}[Skipping]${LIGHT} $app is already installed${RESET}"
        elif command -v flatpak &>/dev/null && flatpak list --columns=ref 2>/dev/null | grep -q "$app"; then
            echo -e "${YELLOW}[Skipping]${LIGHT} $app is already installed via Flatpak${RESET}"
        else
            if apt-cache show "$app" &>/dev/null 2>&1; then
                echo -e "${PURPLE}[Installing]${LIGHT} Downloading $app...${RESET}"
                sudo apt install -y "$app"
            else
                echo -e "${YELLOW}[Notice]${LIGHT} Package '$app' not found in apt repos, skipping.${RESET}"
            fi
        fi
    done
fi

# Install Python CLI apps via pipx
echo -e "${CYAN_B}Would you like to install listed python apps via pipx? (y/N)${RESET}"
read -t $PROMPT_TIMEOUT -n 1 -r REPLY
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v pipx &>/dev/null; then
        echo -e "${PURPLE}Starting pipx installation...${RESET}"
        for papp in "${python_apps[@]}"; do
            echo -e "${PURPLE}[Installing]${LIGHT} Downloading $papp via pipx...${RESET}"
            pipx install "$papp" || true
        done
        pipx ensurepath
    else
        echo -e "${YELLOW}pipx is not installed. Skipping Python CLI apps.${RESET}"
    fi
fi

# Clean cache
echo -e "${CYAN_B}Would you like to clear unused package caches? (y/N)${RESET}"
read -t $PROMPT_TIMEOUT -n 1 -r REPLY
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${PURPLE}Freeing up disk space...${RESET}"
    sudo apt autoclean -y
fi

echo -e "${PURPLE}Finished installing / updating packages.${RESET}"
