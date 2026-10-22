#!/usr/bin/env bash

set -euo pipefail

PACKAGE_MANAGER="${1:?package manager is required}"
FLATHUB_URL="https://flathub.org/repo/flathub.flatpakrepo"
export PACKAGE_MANAGER FLATHUB_URL
FAILED_APPS=()

run_privileged() {
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

install_native() {
    case "$PACKAGE_MANAGER" in
        apt) run_privileged apt install -y "$@" ;;
        dnf) run_privileged dnf install -y "$@" ;;
        xbps) run_privileged xbps-install -y "$@" ;;
        pkg) run_privileged pkg install -y "$@" ;;
    esac
}

native_package_available() {
    case "$PACKAGE_MANAGER" in
        apt) apt-cache show "$1" >/dev/null 2>&1 ;;
        dnf) dnf -q list --available "$1" >/dev/null 2>&1 ;;
        xbps) xbps-query -Rs "^$1-[0-9]" 2>/dev/null | grep -q . ;;
        pkg) pkg search -e "$1" >/dev/null 2>&1 ;;
    esac
}

ensure_flatpak() {
    if ! command -v flatpak >/dev/null 2>&1; then
        if [[ "$PACKAGE_MANAGER" == pkg ]]; then
            echo "Flatpak is unavailable on FreeBSD; Linux-only apps will be skipped."
            return 1
        fi
        install_native flatpak
    fi

    if ! flatpak remote-list --user --columns=name 2>/dev/null | grep -qx flathub \
        && ! flatpak remote-list --system --columns=name 2>/dev/null | grep -qx flathub; then
        flatpak remote-add --user --if-not-exists flathub "$FLATHUB_URL" || return 1
    fi
}

install_flatpak() {
    local app_id="$1"
    if flatpak info --user "$app_id" >/dev/null 2>&1 || flatpak info --system "$app_id" >/dev/null 2>&1; then
        echo "Already installed: $app_id"
    else
        flatpak install --user -y flathub "$app_id"
    fi
}

install_desktop_app() {
    local package="$1" app_id="$2"
    if command -v flatpak >/dev/null 2>&1 \
        && { flatpak info --user "$app_id" >/dev/null 2>&1 || flatpak info --system "$app_id" >/dev/null 2>&1; }; then
        echo "Already installed: $app_id"
        return
    fi
    if [[ -n "$package" ]] && native_package_available "$package"; then
        install_native "$package"
    elif ensure_flatpak; then
        install_flatpak "$app_id"
    else
        return 1
    fi
}

install_conky() {
    if native_package_available conky; then
        install_native conky
    elif native_package_available conky-all; then
        install_native conky-all
    else
        echo "No native package found for conky or conky-all; skipping."
    fi
}

install_vscode() {
    if command -v flatpak >/dev/null 2>&1 \
        && { flatpak info --user com.visualstudio.code >/dev/null 2>&1 || flatpak info --system com.visualstudio.code >/dev/null 2>&1; }; then
        echo "Already installed: com.visualstudio.code"
        return
    fi
    if native_package_available code; then
        install_native code
        return
    fi

    case "$PACKAGE_MANAGER" in
        apt)
            command -v curl >/dev/null 2>&1 || install_native curl
            command -v gpg >/dev/null 2>&1 || install_native gnupg
            local key_file
            key_file="$(mktemp)"
            curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$key_file"
            run_privileged install -D -m 0644 "$key_file" /usr/share/keyrings/microsoft.gpg
            rm -f "$key_file"
            printf 'deb [arch=%s signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main\n' "$(dpkg --print-architecture)" \
                | run_privileged tee /etc/apt/sources.list.d/vscode.list >/dev/null
            run_privileged apt update
            install_native code
            ;;
        dnf)
            printf '%s\n' '[code]' 'name=Visual Studio Code' 'baseurl=https://packages.microsoft.com/yumrepos/vscode' 'enabled=1' 'autorefresh=1' 'type=rpm-md' 'gpgcheck=1' 'gpgkey=https://packages.microsoft.com/keys/microsoft.asc' \
                | run_privileged tee /etc/yum.repos.d/vscode.repo >/dev/null
            install_native code
            ;;
        *) install_desktop_app '' com.visualstudio.code ;;
    esac
}

install_helium() {
    case "$PACKAGE_MANAGER" in
        apt)
            if ! dpkg-query -W -f='${Status}' helium-bin 2>/dev/null | grep -q 'install ok installed'; then
                command -v curl >/dev/null 2>&1 || install_native curl
                command -v gpg >/dev/null 2>&1 || install_native gnupg
                local key_file
                key_file="$(mktemp)"
                curl -fsSL https://raw.githubusercontent.com/imputnet/helium-linux/main/pubkey.asc | gpg --dearmor > "$key_file"
                run_privileged install -D -m 0644 "$key_file" /usr/share/keyrings/helium.gpg
                rm -f "$key_file"
                printf '%s\n' 'deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/helium.gpg] https://pkg.helium.computer/deb stable main' \
                    | run_privileged tee /etc/apt/sources.list.d/helium.list >/dev/null
                run_privileged apt update
                install_native helium-bin
            fi
            ;;
        dnf)
            if ! rpm -q helium-bin >/dev/null 2>&1; then
                dnf copr --help >/dev/null 2>&1 || install_native dnf-plugins-core
                run_privileged dnf copr enable -y imput/helium
                install_native helium-bin
            fi
            ;;
        *)
            echo "Helium's official Linux packages support Debian/Ubuntu and Fedora; skipping on $PACKAGE_MANAGER."
            ;;
    esac
}

install_sniffnet() {
    local arch asset_url package_file
    case "$PACKAGE_MANAGER" in
        apt|dnf) ;;
        *) echo "Sniffnet's official Linux packages support Debian/Ubuntu and Fedora; skipping on $PACKAGE_MANAGER."; return 0 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64) arch=x86_64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) echo "Sniffnet has no supported release for $(uname -m); skipping."; return 0 ;;
    esac
    command -v curl >/dev/null 2>&1 || install_native curl
    command -v jq >/dev/null 2>&1 || install_native jq

    case "$PACKAGE_MANAGER" in
        apt)
            asset_url="$(curl -fsSL https://api.github.com/repos/GyulyVGC/sniffnet/releases/latest | jq -r --arg arch "$arch" '.assets[] | select(.name == ("Sniffnet_LinuxDEB_" + (if $arch == "x86_64" then "amd64" else "arm64" end) + ".deb")) | .browser_download_url')"
            package_file="$(mktemp --suffix=.deb)"
            curl -fL "$asset_url" -o "$package_file"
            chmod 644 "$package_file"
            run_privileged apt install -y "$package_file"
            ;;
        dnf)
            asset_url="$(curl -fsSL https://api.github.com/repos/GyulyVGC/sniffnet/releases/latest | jq -r --arg arch "$arch" '.assets[] | select(.name == ("Sniffnet_LinuxRPM_" + $arch + ".rpm")) | .browser_download_url')"
            package_file="$(mktemp --suffix=.rpm)"
            curl -fL "$asset_url" -o "$package_file"
            run_privileged dnf install -y "$package_file"
            ;;
        *)
            echo "Sniffnet's official Linux packages support Debian/Ubuntu and Fedora; skipping on $PACKAGE_MANAGER."
            ;;
    esac
    [[ -z "${package_file:-}" ]] || rm -f "$package_file"
}

install_appimagelauncher() {
    local arch api_url release_data asset_url digest package_file
    if native_package_available appimagelauncher; then
        install_native appimagelauncher
        return
    fi
    if [[ "$PACKAGE_MANAGER" == pkg ]]; then
        echo "AppImageLauncher is not available for FreeBSD; skipping."
        return 0
    fi

    case "$(uname -m)" in
        x86_64|amd64) arch=x86_64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) echo "AppImageLauncher has no supported release for $(uname -m); skipping."; return 0 ;;
    esac
    command -v curl >/dev/null 2>&1 || install_native curl
    command -v jq >/dev/null 2>&1 || install_native jq
    api_url="https://api.github.com/repos/TheAssassin/AppImageLauncher/releases/latest"
    release_data="$(curl -fsSL "$api_url")"

    case "$PACKAGE_MANAGER:$arch" in
        apt:x86_64) asset_url="$(jq -r '.assets[] | select(.name | startswith("appimagelauncher_") and endswith("_amd64.deb")) | .browser_download_url' <<< "$release_data" | head -n 1)"; digest="$(jq -r '.assets[] | select(.name | startswith("appimagelauncher_") and endswith("_amd64.deb")) | .digest' <<< "$release_data" | head -n 1 | cut -d: -f2)" ;;
        apt:aarch64) asset_url="$(jq -r '.assets[] | select(.name | startswith("appimagelauncher_") and endswith("_arm64.deb")) | .browser_download_url' <<< "$release_data" | head -n 1)"; digest="$(jq -r '.assets[] | select(.name | startswith("appimagelauncher_") and endswith("_arm64.deb")) | .digest' <<< "$release_data" | head -n 1 | cut -d: -f2)" ;;
        dnf:x86_64) asset_url="$(jq -r '.assets[] | select(.name | startswith("appimagelauncher_") and endswith("_x86_64.rpm")) | .browser_download_url' <<< "$release_data" | head -n 1)"; digest="$(jq -r '.assets[] | select(.name | startswith("appimagelauncher_") and endswith("_x86_64.rpm")) | .digest' <<< "$release_data" | head -n 1 | cut -d: -f2)" ;;
        dnf:aarch64) asset_url="$(jq -r '.assets[] | select(.name | startswith("appimagelauncher_") and endswith("_aarch64.rpm")) | .browser_download_url' <<< "$release_data" | head -n 1)"; digest="$(jq -r '.assets[] | select(.name | startswith("appimagelauncher_") and endswith("_aarch64.rpm")) | .digest' <<< "$release_data" | head -n 1 | cut -d: -f2)" ;;
        xbps:*) asset_url="$(jq -r --arg arch "$arch" '.assets[] | select(.name | startswith("appimagelauncher-lite-") and endswith("-" + $arch + ".AppImage")) | .browser_download_url' <<< "$release_data" | head -n 1)"; digest="$(jq -r --arg arch "$arch" '.assets[] | select(.name | startswith("appimagelauncher-lite-") and endswith("-" + $arch + ".AppImage")) | .digest' <<< "$release_data" | head -n 1 | cut -d: -f2)" ;;
        *) echo "AppImageLauncher is not supported on $PACKAGE_MANAGER; skipping."; return 0 ;;
    esac
    if [[ -z "$asset_url" || -z "$digest" || "$digest" == null ]]; then
        echo "Could not find a verifiable AppImageLauncher package; skipping."
        return 0
    fi

    if [[ "$PACKAGE_MANAGER" == xbps ]]; then
        package_file="$HOME/.local/bin/appimagelauncher-lite.AppImage"
        mkdir -p "$HOME/.local/bin"
        curl -fL "$asset_url" -o "$package_file"
        printf '%s  %s\n' "$digest" "$package_file" | sha256sum -c -
        chmod +x "$package_file"
        "$package_file" install
    else
        package_file="$(mktemp --suffix="$([[ "$PACKAGE_MANAGER" == apt ]] && printf .deb || printf .rpm)")"
        curl -fL "$asset_url" -o "$package_file"
        printf '%s  %s\n' "$digest" "$package_file" | sha256sum -c -
        if [[ "$PACKAGE_MANAGER" == apt ]]; then
            chmod 644 "$package_file"
            run_privileged apt install -y "$package_file"
        else
            run_privileged dnf install -y "$package_file"
        fi
        rm -f "$package_file"
    fi
}

install_if_available() {
    local package="$1"
    if native_package_available "$package"; then
        install_native "$package"
    else
        echo "No native package found for $package; skipping."
    fi
}

setup_kitty_config() {
    local config_dir="$HOME/.config/kitty"
    mkdir -p "$config_dir"
    if [[ ! -e "$config_dir/kitty.conf" ]]; then
        printf '%s\n' 'background_opacity 0.8' 'initial_window_width 128c' 'initial_window_height 37c' > "$config_dir/kitty.conf"
        echo "Installed Kitty defaults in $config_dir/kitty.conf"
    else
        echo "Keeping existing Kitty config: $config_dir/kitty.conf"
    fi
}

install_ge_proton() {
    local arch api_url release_data release_tag asset_url digest archive steam_dir target_dir
    case "$(uname -m)" in
        x86_64|amd64) arch=x86_64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) echo "GE-Proton has no supported release for $(uname -m); skipping."; return 0 ;;
    esac
    command -v curl >/dev/null 2>&1 || install_native curl
    command -v jq >/dev/null 2>&1 || install_native jq
    api_url="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"
    release_data="$(curl -fsSL "$api_url")"
    release_tag="$(jq -r '.tag_name' <<< "$release_data")"
    if flatpak info --user com.valvesoftware.Steam >/dev/null 2>&1 || flatpak info --system com.valvesoftware.Steam >/dev/null 2>&1; then
        steam_dir="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    elif [[ -d "$HOME/.steam/root" ]]; then
        steam_dir="$HOME/.steam/root"
    else
        steam_dir="$HOME/.local/share/Steam"
    fi
    target_dir="$steam_dir/compatibilitytools.d"
    if [[ -d "$target_dir/$release_tag" ]]; then
        echo "Already installed: $release_tag"
        return 0
    fi
    asset_url="$(jq -r --arg arch "$arch" '.assets[] | select(.name | endswith("-" + $arch + ".tar.gz")) | .browser_download_url' <<< "$release_data" | head -n 1)"
    digest="$(jq -r --arg arch "$arch" '.assets[] | select(.name | endswith("-" + $arch + ".tar.gz")) | .digest' <<< "$release_data" | head -n 1 | cut -d: -f2)"
    if [[ -z "$asset_url" || -z "$digest" || "$digest" == null ]]; then
        echo "Could not find a verifiable GE-Proton archive for $arch; skipping."
        return 0
    fi

    mkdir -p "$target_dir"
    archive="$(mktemp --suffix=.tar.gz)"
    curl -fL "$asset_url" -o "$archive"
    printf '%s  %s\n' "$digest" "$archive" | sha256sum -c -
    tar -xzf "$archive" -C "$target_dir"
    rm -f "$archive"
}

run_app() {
    local app="$1" status
    shift
    if "$BASH" -euo pipefail -c '"$@"' bash "$@"; then
        return 0
    else
        status=$?
        printf 'ERROR: %s was not installed (exit status %s); continuing.\n' "$app" "$status" >&2
        FAILED_APPS+=("$app")
    fi
}

if ! command -v "$PACKAGE_MANAGER" >/dev/null 2>&1; then
    echo "Required package manager '$PACKAGE_MANAGER' was not found."
    exit 1
fi

echo "Installing GUI applications for $PACKAGE_MANAGER..."
export -f $(compgen -A function)
run_app "Kitty" install_if_available kitty
run_app "Conky" install_conky
run_app "AppImageLauncher" install_appimagelauncher
run_app "Kitty configuration" setup_kitty_config
run_app "Helium" install_helium
run_app "Sniffnet" install_sniffnet

run_app "Discord" install_desktop_app discord com.discordapp.Discord
run_app "Spotify" install_desktop_app spotify-client com.spotify.Client
run_app "Visual Studio Code" install_vscode

if [[ -t 0 ]]; then
    read -r -p 'Is this a gaming setup? (y/N) ' gaming_setup
else
    gaming_setup="n"
fi
if [[ "$gaming_setup" =~ ^[Yy]$ ]]; then
    run_app "Steam" install_desktop_app steam-installer com.valvesoftware.Steam
    run_app "ProtonUp-Qt" install_desktop_app '' net.davidotek.pupgui2
    run_app "GE-Proton" install_ge_proton
fi

if ((${#FAILED_APPS[@]})); then
    printf 'Apps not installed: %s\n' "${FAILED_APPS[*]}" >&2
fi
echo "GUI application setup complete."