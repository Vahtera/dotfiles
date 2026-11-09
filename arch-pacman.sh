#!/usr/bin/env bash
################################################################
### Arch Linux / Arch-based Pacman Package Install & Update Script
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

echo -e "${PURPLE}Starting Arch Linux/Arch-based Pacman package install & update script${RESET}"
echo -e "${YELLOW}Before proceeding, ensure you are happy with the packages listed in ${0##*/}${RESET}\n"

if ! command -v pacman &>/dev/null; then
    echo -e "${YELLOW}pacman package manager does not exist on this system. Exiting.${RESET}"
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

arch_package_name() {
    case "$1" in
        gh) echo github-cli ;;
        golang) echo go ;;
        pipx|python3-pipx|py311-pipx) echo python-pipx ;;
        python3-full|python3|python311) echo python ;;
        *) echo "$1" ;;
    esac
}

arch_package_available() {
    local package
    package="$(arch_package_name "$1")"
    pacman -Si "$package" &>/dev/null
}

package_installed() {
    local package
    package="$(arch_package_name "$1")"
    pacman -Q "$package" &>/dev/null
}

installed=()
skipped=()
failed=()

if ask "Would you like to synchronize package databases and upgrade the system?"; then
    run_privileged pacman -Syu --noconfirm
fi

if ask "Would you like to install listed apps?"; then
    for app_line in "${apps[@]}"; do
        parse_app_alternatives "$app_line"
        app="${APP_ALTERNATIVES[0]}"
        installed_app=""
        for candidate in "${APP_ALTERNATIVES[@]}"; do
            if package_installed "$candidate"; then
                installed_app="$(arch_package_name "$candidate")"
                break
            elif command -v "$candidate" &>/dev/null; then
                installed_app="$candidate"
                break
            elif command -v flatpak &>/dev/null && flatpak list --columns=ref 2>/dev/null | grep -q "$candidate"; then
                installed_app="$candidate"
                break
            fi
        done
        if [[ -n "$installed_app" ]]; then
            echo -e "${YELLOW}[Skipping]${LIGHT} $installed_app is already installed${RESET}"
            skipped+=("$app_line")
        elif select_available_app arch_package_available "$app_line"; then
            app="$(arch_package_name "$APP_SELECTED")"
            if run_privileged pacman -S --needed --noconfirm "$app"; then
                installed+=("$app")
            else
                echo -e "${YELLOW}[Warning]${LIGHT} Could not install $app from Pacman repositories.${RESET}"
                failed+=("$app")
            fi
        else
            echo -e "${YELLOW}[Warning]${LIGHT} No package in '$app_line' was found in Pacman repositories.${RESET}"
            failed+=("$app_line")
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

if ask "Would you like to clear the Pacman package cache?"; then
    run_privileged pacman -Sc --noconfirm
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
print_list "Pacman installed" "${installed[@]}"
print_list "Pacman skipped (already installed)" "${skipped[@]}"
print_list "Pacman failed or unavailable" "${failed[@]}"
echo -e "\n${PURPLE}Finished installing / updating packages.${RESET}"