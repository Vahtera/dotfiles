#!/usr/bin/env bash
################################################################
### FreeBSD pkg Package Install & Update Script
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

echo -e "${PURPLE}Starting FreeBSD pkg package install & update script${RESET}"
echo -e "${YELLOW}Before proceeding, ensure you are happy with the packages listed in ${0##*/}${RESET}\n"

if ! command -v pkg &>/dev/null; then
    echo -e "${YELLOW}pkg package manager does not exist on this system. Exiting.${RESET}"
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

bsd_apps=(
    git neovim ranger tmux wget zsh gh lynx elinks aria2 bat broot ctags
    diff-so-fancy duf fzf hyperfine just jq most procs ripgrep sd thefuck tree
    tokei trash-cli xsel zoxide qalc go python311 node bsdgames py311-pipx
    rubygem-lolcat clamav cryptsetup gnupg git-crypt lynis openssl rkhunter
    btop bmon ctop gping glances goaccess speedtest-cli wavemon sysbench
    cowsay figlet nudoku trippy nvtop eza fastfetch tealdeer
)

installed=()
skipped=()
failed=()

if ask "Would you like to refresh the pkg repository metadata?"; then
    run_privileged pkg update
fi

if ask "Would you like to upgrade currently installed packages?"; then
    run_privileged pkg upgrade -y
fi

if ask "Would you like to install listed apps?"; then
    for app in "${bsd_apps[@]}"; do
        if pkg info -e "$app" &>/dev/null; then
            echo -e "${YELLOW}[Skipping]${LIGHT} $app is already installed${RESET}"
            skipped+=("$app")
        elif run_privileged pkg install -y "$app"; then
            installed+=("$app")
        else
            echo -e "${YELLOW}[Warning]${LIGHT} Could not install $app from pkg repositories.${RESET}"
            failed+=("$app")
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

if ask "Would you like to clear the pkg cache?"; then
    run_privileged pkg clean -ay
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
print_list "pkg installed" "${installed[@]}"
print_list "pkg skipped (already installed)" "${skipped[@]}"
print_list "pkg failed" "${failed[@]}"
echo -e "\n${PURPLE}Finished installing / updating packages.${RESET}"