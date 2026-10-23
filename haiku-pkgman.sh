#!/usr/bin/env bash
################################################################
### Haiku pkgman CLI Package Install & Update Script
################################################################

PURPLE='\033[0;35m'
YELLOW='\033[0;93m'
CYAN_B='\033[1;96m'
LIGHT='\x1b[2m'
RESET='\033[0m'

PROMPT_TIMEOUT=15
AUTO_YES=0
if [[ " $* " == *" --auto-yes "* ]]; then
    AUTO_YES=1
fi

echo -e "${PURPLE}Starting Haiku pkgman package install & update script${RESET}"
echo -e "${YELLOW}Before proceeding, ensure you are happy with the packages listed in ${0##*/}${RESET}\n"

if ! command -v pkgman &>/dev/null; then
    echo -e "${YELLOW}pkgman does not exist on this system. Exiting.${RESET}"
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${PURPLE}Elevated permissions are required to install packages.${RESET}"
    echo -e "${CYAN_B}Please enter your password...${RESET}"
    if ! sudo -v; then
        echo -e "${YELLOW}Exiting, as sudo authentication failed.${RESET}"
        exit 1
    fi
fi

run_privileged() {
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

ask() {
    local prompt="$1"
    if [[ "$AUTO_YES" -eq 1 ]]; then
        echo -e "${CYAN_B}${prompt} (auto-yes)${RESET}"
        return 0
    fi
    echo -e "${CYAN_B}${prompt} (y/N)${RESET}"
    REPLY=""
    read -t "$PROMPT_TIMEOUT" -n 1 -r REPLY || true
    echo
    [[ "$REPLY" =~ ^[Yy]$ ]]
}

haiku_apps=(
    git neovim ranger tmux wget zsh
    lynx elinks jq tree ctags most qalc
    bat fzf ripgrep zoxide aria2 hyperfine just
    golang nodejs npm python3
    gnupg openssl git-crypt clamav
    btop bmon glances goaccess sysbench
    cowsay figlet lolcat wordgrinder nudoku
)

installed=()
skipped=()
failed=()

if ask "Would you like to refresh the pkgman repository metadata?"; then
    run_privileged pkgman update
fi

if ask "Would you like to upgrade currently installed packages?"; then
    run_privileged pkgman full-sync
fi

package_installed() {
    pkgman search -i -s name "$1" 2>/dev/null \
        | awk -v package="$1" '$2 == package { found = 1 } END { exit !found }'
}

install_package() {
    local package="$1"
    if package_installed "$package"; then
        echo -e "${YELLOW}[Skipping]${LIGHT} $package is already installed${RESET}"
        skipped+=("$package")
    elif run_privileged pkgman install -y "$package"; then
        installed+=("$package")
    else
        echo -e "${YELLOW}[Warning]${LIGHT} Could not install $package from Haiku repositories.${RESET}"
        failed+=("$package")
    fi
}

install_alternative() {
    local primary="$1"
    local fallback="$2"
    if package_installed "$primary" || package_installed "$fallback"; then
        echo -e "${YELLOW}[Skipping]${LIGHT} Either $primary or $fallback is already installed.${RESET}"
        skipped+=("$primary/$fallback")
    elif run_privileged pkgman install -y "$primary"; then
        installed+=("$primary")
    elif run_privileged pkgman install -y "$fallback"; then
        installed+=("$fallback")
    else
        echo -e "${YELLOW}[Warning]${LIGHT} Neither $primary nor $fallback could be installed from Haiku repositories.${RESET}"
        failed+=("$primary/$fallback")
    fi
}

if ask "Would you like to install listed apps?"; then
    install_alternative eza exa
    install_alternative fastfetch neofetch
    install_alternative tealdeer tldr
    for app in "${haiku_apps[@]}"; do
        install_package "$app"
    done
fi

print_list() {
    local title="$1"
    shift
    echo -e "\n${CYAN_B}${title} (${#@}):${RESET}"
    if [[ "$#" -eq 0 ]]; then
        echo "  None"
    else
        printf '  - %s\n' "$@"
    fi
}

echo -e "\n${PURPLE}========================================${RESET}"
echo -e "${PURPLE} Installation Summary${RESET}"
echo -e "${PURPLE}========================================${RESET}"
print_list "pkgman installed" "${installed[@]}"
print_list "pkgman skipped (already installed)" "${skipped[@]}"
print_list "pkgman failed" "${failed[@]}"
echo -e "\n${PURPLE}Finished installing / updating packages.${RESET}"