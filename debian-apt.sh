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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -r "$SCRIPT_DIR/apps-common.sh" ]]; then
    SCRIPT_DIR="$HOME/.local/bin"
fi
if ! source "$SCRIPT_DIR/apps-common.sh"; then
    exit 1
fi

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

ensure_spotify_apt_key() {
    local key_file key_url="https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.gpg"
    if ! grep -Rqs 'repository.spotify.com' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        return 0
    fi

    key_file="$(mktemp)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$key_url" -o "$key_file"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$key_file" "$key_url"
    else
        rm -f "$key_file"
        echo -e "${YELLOW}Cannot update Spotify's apt key: curl or wget is required.${RESET}"
        return 1
    fi

    if ! gpg --show-keys --with-colons "$key_file" 2>/dev/null \
        | awk -F: '$1 == "fpr" && substr($10, length($10) - 15) == "5384CE82BA52C83A" { found = 1 } END { exit !found }'; then
        rm -f "$key_file"
        echo -e "${YELLOW}Spotify's downloaded apt key did not match the expected key ID.${RESET}"
        return 1
    fi

    if ! gpg --dearmor --yes --output "$key_file.gpg" "$key_file" \
        || ! sudo install -m 0644 "$key_file.gpg" /etc/apt/trusted.gpg.d/spotify.gpg; then
        rm -f "$key_file" "$key_file.gpg"
        return 1
    fi
    rm -f "$key_file" "$key_file.gpg"
}

ensure_spotify_apt_key || exit 1

apt_package_available() {
    apt-cache show "$1" 2>/dev/null \
        | awk -v package="$1" '$1 == "Package:" && $2 == package { found = 1 } END { exit !found }'
}

apt_installed=()
apt_skipped=()
apt_failed=()
apt_unavailable=()

pipx_installed=()
pipx_failed=()

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
    
    for app_line in "${apps[@]}"; do
        parse_app_alternatives "$app_line"
        app="${APP_ALTERNATIVES[0]}"
        installed_app=""
        for candidate in "${APP_ALTERNATIVES[@]}"; do
            if command -v "$candidate" &>/dev/null; then
                installed_app="$candidate"
                break
            elif command -v flatpak &>/dev/null && flatpak list --columns=ref 2>/dev/null | grep -q "$candidate"; then
                installed_app="$candidate"
                break
            fi
        done
        if [[ -n "$installed_app" ]]; then
            echo -e "${YELLOW}[Skipping]${LIGHT} $installed_app is already installed${RESET}"
            apt_skipped+=("$app_line")
        elif select_available_app apt_package_available "$app_line"; then
            app="$APP_SELECTED"
            echo -e "${PURPLE}[Installing]${LIGHT} Downloading $app...${RESET}"
            if sudo apt install -y "$app"; then
                apt_installed+=("$app")
                mark_go_installed "$app"
            else
                apt_failed+=("$app")
            fi
        else
            echo -e "${YELLOW}[Notice]${LIGHT} No package in '$app_line' was found in apt repos, skipping.${RESET}"
            apt_unavailable+=("$app_line")
        fi
    done

    if command -v npm &>/dev/null; then
        if npm install --prefix "$HOME/.local/share/font-logos" font-logos; then
            if mkdir -p "$HOME/.local/share/fonts" \
                && cp "$HOME/.local/share/font-logos/node_modules/font-logos/assets/font-logos.ttf" "$HOME/.local/share/fonts/"; then
                if command -v fc-cache &>/dev/null; then
                    fc-cache -f "$HOME/.local/share/fonts" || echo -e "${YELLOW}[Notice] Could not refresh the font cache.${RESET}"
                fi
            else
                echo -e "${YELLOW}[Warning] Could not install the Font Logos font file.${RESET}"
            fi
        else
            echo -e "${YELLOW}[Warning] Could not install font-logos via npm.${RESET}"
        fi
    else
        echo -e "${YELLOW}[Notice] npm is unavailable; skipping font-logos.${RESET}"
    fi
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

echo
echo -e "${PURPLE}========================================${RESET}"
echo -e "${PURPLE} Installation Summary${RESET}"
echo -e "${PURPLE}========================================${RESET}"

print_list() {
    local title="$1"
    shift
    echo
    echo -e "${CYAN_B}${title} (${#@}):${RESET}"
    if [ "$#" -eq 0 ]; then
        echo "  None"
    else
        printf '  - %s\n' "$@"
    fi
}

print_list "APT installed" "${apt_installed[@]}"
print_list "APT skipped (already installed)" "${apt_skipped[@]}"
print_list "APT failed" "${apt_failed[@]}"
print_list "APT unavailable" "${apt_unavailable[@]}"
print_list "pipx installed" "${pipx_installed[@]}"
print_list "pipx failed" "${pipx_failed[@]}"

echo
echo -e "${PURPLE}Finished installing / updating packages.${RESET}"
install_wordterm_if_go_installed
