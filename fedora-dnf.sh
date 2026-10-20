#!/usr/bin/env bash
################################################################
### Fedora / RHEL-family DNF Package Install & Update Script
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

echo -e "${PURPLE}Starting Fedora/RHEL DNF package install & update script${RESET}"
echo -e "${YELLOW}Before proceeding, ensure you are happy with the packages listed in ${0##*/}${RESET}\n"

if ! command -v dnf &>/dev/null; then
    echo -e "${YELLOW}dnf package manager does not exist on this system. Exiting.${RESET}"
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

install_alternative() {
    local primary="$1"
    local fallback="$2"
    if command -v "$primary" &>/dev/null || command -v "$fallback" &>/dev/null; then
        echo -e "${YELLOW}[Skipping]${LIGHT} Either $primary or $fallback is already installed.${RESET}"
    elif run_privileged dnf install -y "$primary"; then
        installed+=("$primary")
    elif run_privileged dnf install -y "$fallback"; then
        installed+=("$fallback")
    else
        echo -e "${YELLOW}[Warning] Neither $primary nor $fallback could be installed from DNF repositories.${RESET}"
        failed+=("$primary/$fallback")
    fi
}

package_installed() {
    rpm -q "$1" &>/dev/null
}

fedora_apps=(
    git neovim ranger tmux wget zsh pipx gh lynx elinks aria2 bat broot ctags
    diff-so-fancy duf fzf hyperfine just jq most procs ripgrep scrot sd thefuck
    tree tokei trash-cli xsel zoxide qalc golang nodejs npm python3
    clamav cryptsetup gnupg git-crypt lynis openssl rkhunter btop bmon ctop
    gping glances goaccess speedtest-cli wavemon sysbench cowsay figlet lolcat
    wordgrinder nudoku nvtop bsd-games trippy
)
python_apps=(epy-reader lazygit tuir)

installed=()
skipped=()
failed=()

if ask "Would you like to refresh the DNF package metadata?"; then
    run_privileged dnf makecache
fi

if ask "Would you like to upgrade currently installed packages?"; then
    run_privileged dnf upgrade -y
fi

if ask "Would you like to install listed apps?"; then
    install_alternative eza exa
    install_alternative fastfetch neofetch
    install_alternative tealdeer tldr
    for app in "${fedora_apps[@]}"; do
        if package_installed "$app"; then
            echo -e "${YELLOW}[Skipping]${LIGHT} $app is already installed${RESET}"
            skipped+=("$app")
        elif command -v flatpak &>/dev/null && flatpak list --columns=ref 2>/dev/null | grep -q "$app"; then
            echo -e "${YELLOW}[Skipping]${LIGHT} $app is already installed via Flatpak${RESET}"
            skipped+=("$app")
        elif run_privileged dnf install -y "$app"; then
            installed+=("$app")
        else
            echo -e "${YELLOW}[Warning]${LIGHT} Could not install $app from DNF repositories.${RESET}"
            failed+=("$app")
        fi
    done
fi

if ask "Would you like to install listed Python apps via pipx?"; then
    if command -v pipx &>/dev/null; then
        for app in "${python_apps[@]}"; do
            pipx install "$app" || true
        done
        pipx ensurepath
    else
        echo -e "${YELLOW}pipx is not installed. Skipping Python CLI apps.${RESET}"
    fi
fi

if ask "Would you like to clear the DNF package cache?"; then
    run_privileged dnf clean all
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
print_list "DNF installed" "${installed[@]}"
print_list "DNF skipped (already installed)" "${skipped[@]}"
print_list "DNF failed" "${failed[@]}"
echo -e "\n${PURPLE}Finished installing / updating packages.${RESET}"
