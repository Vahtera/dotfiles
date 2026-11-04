#!/usr/bin/env bash
################################################################
### Haiku pkgman CLI Package Install & Update Script
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
    local app_line="$1" candidate installed_app=""
    parse_app_alternatives "$app_line"
    for candidate in "${APP_ALTERNATIVES[@]}"; do
        if package_installed "$candidate"; then
            installed_app="$candidate"
            break
        fi
    done
    if [[ -n "$installed_app" ]]; then
        echo -e "${YELLOW}[Skipping]${LIGHT} $installed_app is already installed${RESET}"
        skipped+=("$app_line")
    elif select_available_app haiku_package_available "$app_line"; then
        candidate="$APP_SELECTED"
        if run_privileged pkgman install -y "$candidate"; then
            installed+=("$candidate")
        else
            echo -e "${YELLOW}[Warning]${LIGHT} Could not install $candidate from Haiku repositories.${RESET}"
            failed+=("$candidate")
        fi
    else
        echo -e "${YELLOW}[Warning]${LIGHT} No package in '$app_line' was found in Haiku repositories.${RESET}"
        failed+=("$app_line")
    fi
}

haiku_package_available() {
    pkgman search -s name "$1" 2>/dev/null \
        | awk -v package="$1" '$2 == package { found = 1 } END { exit !found }'
}

if ask "Would you like to install listed apps?"; then
    for app in "${apps[@]}"; do
        install_package "$app"
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