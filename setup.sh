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
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"

# sshd, ufw, nft, iptables, ... live in sbin directories that a regular user's PATH
# often lacks (e.g. Debian), which makes `command -v` miss tools that are installed.
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

echo -e "${CYAN}====================================================${RESET}"
echo -e "${PURPLE}   Setting up Dotfiles for user: ${YELLOW}$USER${RESET}"
echo -e "${CYAN}====================================================${RESET}\n"

# Determine directory if running from a local clone. With `bash -c "$(curl ...)"`
# BASH_SOURCE is empty and dirname would resolve to the current directory, so only
# treat this as a clone when the script is a real file.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
fi

LOCAL_BIN="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config"
mkdir -p "$LOCAL_BIN"
mkdir -p "$CONFIG_DIR/ohmyposh"

# Helper function to fetch files locally or from GitHub raw URL
fetch_file() {
    local filename="$1"
    local dest="$2"

    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$filename" ]; then
        cp "$SCRIPT_DIR/$filename" "$dest"
        return
    fi

    local tmp rc=0
    tmp="$(mktemp)" || return 1
    if command -v curl &>/dev/null; then
        curl -fsSL "$REPO_RAW_URL/$filename" -o "$tmp" || rc=$?
    elif command -v wget &>/dev/null; then
        wget -qO "$tmp" "$REPO_RAW_URL/$filename" || rc=$?
    else
        echo -e "${YELLOW}❌ Error: Could not locate $filename locally nor via curl/wget.${RESET}"
        rc=1
    fi

    if [ "$rc" -eq 0 ]; then
        cat "$tmp" > "$dest" || rc=$?
    else
        echo -e "${YELLOW}❌ Could not download $filename (exit $rc).${RESET}"
    fi
    rm -f "$tmp"
    return "$rc"
}

run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    elif [ "$(uname -s)" = FreeBSD ]; then
        doas "$@"
    else
        sudo "$@"
    fi
}

ssh_server_listening() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltnH 'sport = :22' 2>/dev/null | grep -q .
    elif command -v sockstat >/dev/null 2>&1; then
        sockstat -4 -6 -l -P tcp -p 22 2>/dev/null | grep -q sshd
    else
        (exec 3<>/dev/tcp/127.0.0.1/22) >/dev/null 2>&1
    fi
}

allow_ssh_nft_chain() {
    local family="$1"
    if ! run_privileged nft list chain "$family" filter input >/dev/null 2>&1; then
        return 1
    fi
    if ! run_privileged nft list chain "$family" filter input 2>/dev/null | grep -Eq 'tcp dport 22 accept'; then
        run_privileged nft insert rule "$family" filter input tcp dport 22 accept
    fi
}

setup_ssh_server() {
    local ssh_package="openssh-server"
    local ssh_service="sshd"

    case "$PACKAGE_SCRIPT" in
        debian-apt.sh) ssh_service="ssh" ;;
        arch-pacman.sh) ssh_package="openssh" ;;
        void-xbps.sh) ssh_package="openssh" ;;
        freebsd-pkg.sh) ssh_package="openssh" ;;
    esac

    if ! command -v sshd >/dev/null 2>&1; then
        echo -e "${CYAN}Installing SSH server ($ssh_package)...${RESET}"
        case "$PACKAGE_SCRIPT" in
            debian-apt.sh) run_privileged apt-get update; run_privileged apt-get install -y "$ssh_package" ;;
            arch-pacman.sh) run_privileged pacman -S --needed --noconfirm "$ssh_package" ;;
            fedora-dnf.sh) run_privileged dnf install -y "$ssh_package" ;;
            void-xbps.sh) run_privileged xbps-install -y "$ssh_package" ;;
            freebsd-pkg.sh) run_privileged pkg install -y "$ssh_package" ;;
        esac
    fi

    if ! command -v sshd >/dev/null 2>&1; then
        echo -e "${YELLOW}SSH server is unavailable; skipping service and firewall setup.${RESET}"
        return
    fi
    # Host keys may not exist yet (some distros create them on first service start),
    # which would make `sshd -t` fail even though the configuration is fine.
    run_privileged ssh-keygen -A >/dev/null 2>&1 || true
    if ! run_privileged sshd -t; then
        echo -e "${YELLOW}SSH server configuration is invalid; not starting sshd.${RESET}"
        return
    fi

    case "$PACKAGE_SCRIPT" in
        freebsd-pkg.sh)
            run_privileged sysrc sshd_enable=YES
            if ! service sshd onestatus >/dev/null 2>&1; then
                run_privileged service sshd start
            fi
            ;;
        void-xbps.sh)
            if [ ! -e /var/service/sshd ]; then
                run_privileged ln -s /etc/sv/sshd /var/service/sshd
            fi
            if command -v sv >/dev/null 2>&1; then
                run_privileged sv up sshd
            fi
            ;;
        *)
            if command -v systemctl >/dev/null 2>&1; then
                run_privileged systemctl enable --now "$ssh_service"
            else
                echo -e "${YELLOW}systemctl is unavailable; start sshd manually to accept SSH connections.${RESET}"
            fi
            ;;
    esac

    if ! ssh_server_listening; then
        echo -e "${YELLOW}SSH service is not listening on TCP port 22; firewall rules were not changed.${RESET}"
        return
    fi

    if command -v ufw >/dev/null 2>&1 && run_privileged ufw status 2>/dev/null | grep -q '^Status: active'; then
        run_privileged ufw allow 22/tcp
        echo -e "${GREEN}Allowed SSH through UFW (TCP port 22).${RESET}"
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        if ! firewall-cmd --query-service=ssh >/dev/null 2>&1; then
            run_privileged firewall-cmd --permanent --add-service=ssh
            run_privileged firewall-cmd --reload
        fi
        echo -e "${GREEN}Allowed SSH through firewalld (TCP port 22).${RESET}"
    elif command -v nft >/dev/null 2>&1 && run_privileged nft list ruleset 2>/dev/null | grep -Eq 'hook input'; then
        if allow_ssh_nft_chain inet || allow_ssh_nft_chain ip || allow_ssh_nft_chain ip6; then
            echo -e "${GREEN}Allowed SSH through nftables for the current ruleset (TCP port 22).${RESET}"
            echo -e "${YELLOW}Persist the rule in your nftables configuration if your rules are reloaded at boot.${RESET}"
        else
            echo -e "${YELLOW}An nftables firewall is active, but no standard filter input chain was found; allow inbound TCP port 22 in your nftables rules.${RESET}"
        fi
    elif command -v iptables >/dev/null 2>&1 && run_privileged iptables -S INPUT 2>/dev/null | grep -Eq '^-P INPUT (DROP|REJECT)|^-A INPUT'; then
        if ! run_privileged iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null; then
            run_privileged iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
        fi
        if command -v ip6tables >/dev/null 2>&1 && run_privileged ip6tables -S INPUT 2>/dev/null | grep -Eq '^-P INPUT (DROP|REJECT)|^-A INPUT'; then
            if ! run_privileged ip6tables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null; then
                run_privileged ip6tables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
            fi
        fi
        if command -v netfilter-persistent >/dev/null 2>&1; then
            run_privileged netfilter-persistent save
        else
            echo -e "${YELLOW}Allowed SSH through iptables for this session; no persistent iptables save tool was found.${RESET}"
        fi
    elif command -v ipfw >/dev/null 2>&1 && run_privileged ipfw list 2>/dev/null | grep -q 'deny ip from any to any'; then
        local ipfw_rules rule_number
        ipfw_rules="$(run_privileged ipfw list 2>/dev/null)"
        if ! grep -Eq 'allow tcp .*dst-port 22' <<< "$ipfw_rules"; then
            rule_number=65534
            while grep -q "^$rule_number " <<< "$ipfw_rules" && [ "$rule_number" -gt 1 ]; do
                rule_number=$((rule_number - 1))
            done
            run_privileged ipfw add "$rule_number" allow tcp from any to me 22 in
        fi
        echo -e "${GREEN}Allowed SSH through ipfw for the current ruleset (TCP port 22).${RESET}"
        echo -e "${YELLOW}Persist the rule in your FreeBSD firewall configuration if rules are reloaded at boot.${RESET}"
    elif command -v pfctl >/dev/null 2>&1 && run_privileged pfctl -s info 2>/dev/null | grep -q 'Status: Enabled'; then
        echo -e "${YELLOW}PF is active. Its rules were left unchanged; allow inbound TCP port 22 in /etc/pf.conf.${RESET}"
    else
        echo -e "${CYAN}No active supported firewall detected; no firewall rules changed.${RESET}"
    fi
}

# 0. Detect the distro (used by the SSH setup and the package installer step)
PACKAGE_SCRIPT=""
if [ -r "$OS_RELEASE_FILE" ]; then
    . "$OS_RELEASE_FILE"
    DISTRO_ID="${ID,,}"
    DISTRO_LIKE=" ${ID_LIKE,,} "

    case "$DISTRO_ID" in
        arch) PACKAGE_SCRIPT="arch-pacman.sh" ;;
        debian|ubuntu|linuxmint|pop|raspbian|kali) PACKAGE_SCRIPT="debian-apt.sh" ;;
        fedora|rhel|centos|rocky|almalinux|nobara) PACKAGE_SCRIPT="fedora-dnf.sh" ;;
        freebsd) PACKAGE_SCRIPT="freebsd-pkg.sh" ;;
        void) PACKAGE_SCRIPT="void-xbps.sh" ;;
        haiku) PACKAGE_SCRIPT="haiku-pkgman.sh" ;;
        *)
            case "$DISTRO_LIKE" in
                *" arch "*) PACKAGE_SCRIPT="arch-pacman.sh" ;;
                *" debian "*|*" ubuntu "*) PACKAGE_SCRIPT="debian-apt.sh" ;;
                *" fedora "*|*" rhel "*|*" centos "*) PACKAGE_SCRIPT="fedora-dnf.sh" ;;
            esac
            ;;
    esac
fi

if [[ "$(uname -s)" == "Haiku" ]]; then
    PACKAGE_SCRIPT="haiku-pkgman.sh"
fi

# 0.1 Set up the SSH server first, so remote access works even if a later step fails
if [ -n "$PACKAGE_SCRIPT" ] && [ "$PACKAGE_SCRIPT" != "haiku-pkgman.sh" ]; then
    echo -e "${CYAN}[0/5] Setting up the SSH server...${RESET}"
    setup_ssh_server || echo -e "  ${YELLOW}SSH server setup did not complete; continuing.${RESET}"
    echo
fi

# 1. Install CLI tools to $HOME/.local/bin
echo -e "${CYAN}[1/5] Installing CLI tools to $LOCAL_BIN...${RESET}"

if fetch_file "anna.omp.json" "$CONFIG_DIR/ohmyposh/anna.omp.json"; then
    chmod +x "$CONFIG_DIR/ohmyposh/anna.omp.json"
    echo -e "  ${GREEN}✓ Installed OMP Theme${RESET}"
fi

if fetch_file "welcome_banner.sh" "$LOCAL_BIN/welcome_banner.sh"; then
    chmod +x "$LOCAL_BIN/welcome_banner.sh"
    echo -e "  ${GREEN}✓ Installed welcome_banner.sh${RESET}"
fi

if fetch_file "run_benchmark.sh" "$LOCAL_BIN/run_benchmark.sh"; then
    chmod +x "$LOCAL_BIN/run_benchmark.sh"
    echo -e "  ${GREEN}✓ Installed run_benchmark.sh${RESET}"
fi

if fetch_file "install-wordterm.sh" "$LOCAL_BIN/install-wordterm.sh"; then
    chmod +x "$LOCAL_BIN/install-wordterm.sh"
    echo -e "  ${GREEN}✓ Installed install-wordterm.sh${RESET}"
fi

# Only offer this when NetworkManager is available (it is what the script configures)
if command -v nmcli >/dev/null 2>&1 && nmcli general status >/dev/null 2>&1; then
    if [ -c /dev/tty ]; then
        read -r -p 'Disable automatically learned IPv6 DNS? (Y/n) ' REPLY < /dev/tty || REPLY="N"
    else
        read -r -p 'Disable automatically learned IPv6 DNS? (Y/n) ' REPLY || REPLY="N"
    fi
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if fetch_file "disable-ipv6-auto-dns.sh" "$LOCAL_BIN/disable-ipv6-auto-dns.sh"; then
            chmod +x "$LOCAL_BIN/disable-ipv6-auto-dns.sh"
            if ! bash "$LOCAL_BIN/disable-ipv6-auto-dns.sh"; then
                echo -e "  ${YELLOW}IPv6 auto-DNS configuration failed; continuing setup.${RESET}"
            fi
        fi
    fi
fi

# 1.1 Download and install correct Nerdfont for the system
echo -e "\n${CYAN}[1.1/5] Installing Nerd Font...${RESET}"
if fetch_file "install-nerdfont.sh" "$LOCAL_BIN/install-nerdfont.sh"; then
    chmod +x "$LOCAL_BIN/install-nerdfont.sh"
    bash "$LOCAL_BIN/install-nerdfont.sh" \
        || echo -e "  ${YELLOW}Nerd Font installation did not complete; continuing.${RESET}"
else
    echo -e "  ${YELLOW}Could not fetch install-nerdfont.sh; skipping Nerd Font installation.${RESET}"
fi

# 2. Deploy .bash_aliases for bash and zsh
echo -e "\n${CYAN}[2/5] Deploying .bash_aliases...${RESET}"
if fetch_file "bash_aliases" "$HOME/.bash_aliases"; then
    echo -e "  ${GREEN}✓ Copied .bash_aliases to $HOME/.bash_aliases${RESET}"
fi

# 2.1 Deploy .nushell/aliases.nu
echo -e "\n${CYAN}[2.1/5] Deploying nushell aliases.nu...${RESET}"
NUSHELL_CONFIG_DIR="$HOME/.config/nushell"
mkdir -p "$NUSHELL_CONFIG_DIR"
if fetch_file "aliases.nu" "$NUSHELL_CONFIG_DIR/aliases.nu"; then
    echo -e "  ${GREEN}✓ Copied aliases.nu to $NUSHELL_CONFIG_DIR/aliases.nu${RESET}"
fi 


# 3. Update the managed Bash configuration and source it from .bashrc
echo -e "\n${CYAN}[3/5] Updating $HOME/.bashrc...${RESET}"
BASHRC="$HOME/.bashrc"
BASH_CONFIG_DIR="$HOME/.config/shells/bash"
BASHRC_USER="$BASH_CONFIG_DIR/bashrc-user"
mkdir -p "$BASH_CONFIG_DIR"
touch "$BASHRC"

# Install ble.sh if it is not already installed
install_blesh() {
    # lib/ is checked too, so an older install that only copied ble.sh gets repaired
    if [ -f "$HOME/.local/share/blesh/ble.sh" ] && [ -d "$HOME/.local/share/blesh/lib" ]; then
        return 0
    fi
    command -v xz >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 \
        || { echo "xz and tar are required for ble.sh" >&2; return 1; }
    local tmp rc=0; tmp="$(mktemp -d)" || return 1
    curl -fsSL -o "$tmp/ble.tar.xz" \
        https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz \
        && tar xJf "$tmp/ble.tar.xz" -C "$tmp" \
        && bash "$tmp/ble-nightly/ble.sh" --install "$HOME/.local/share" || rc=1
    rm -rf "$tmp"; return $rc
}
install_blesh || echo -e "  ${YELLOW}ble.sh installation failed; continuing.${RESET}"

if fetch_file "bashrc-user" "$BASHRC_USER"; then
    echo -e "  ${GREEN}✓ Updated $BASHRC_USER${RESET}"
fi

BASHRC_SOURCE='[[ -f "$HOME/.config/shells/bash/bashrc-user" ]] && source "$HOME/.config/shells/bash/bashrc-user"'
if ! grep -qF "$BASHRC_SOURCE" "$BASHRC"; then
    printf '\n%s\n' "$BASHRC_SOURCE" >> "$BASHRC"
    echo -e "  ${GREEN}✓ Added the bashrc-user source line to $BASHRC${RESET}"
else
    echo -e "  ${YELLOW}The bashrc-user source line already exists in $BASHRC.${RESET}"
fi

#3.1 Update the managed zsh configuration and source it from .zshrc if zsh is installed
if command -v zsh &>/dev/null; then
    echo -e "\n${CYAN}[3.1/5] Updating $HOME/.zshrc...${RESET}"
    ZSHRC="$HOME/.zshrc"
    ZSH_CONFIG_DIR="$HOME/.config/shells/zsh"
    ZSHRC_USER="$ZSH_CONFIG_DIR/zshrc-user"
    mkdir -p "$ZSH_CONFIG_DIR"
    touch "$ZSHRC"

    if fetch_file "zshrc-user" "$ZSHRC_USER"; then
        echo -e "  ${GREEN}✓ Updated $ZSHRC_USER${RESET}"
    fi

    ZSHRC_SOURCE='[[ -f "$HOME/.config/shells/zsh/zshrc-user" ]] && source "$HOME/.config/shells/zsh/zshrc-user"'
    if ! grep -qF "$ZSHRC_SOURCE" "$ZSHRC"; then
        printf '\n%s\n' "$ZSHRC_SOURCE" >> "$ZSHRC"
        echo -e "  ${GREEN}✓ Added the zshrc-user source line to $ZSHRC${RESET}"
    else
        echo -e "  ${YELLOW}The zshrc-user source line already exists in $ZSHRC.${RESET}"
    fi
fi

#3.2 Update the managed nushell configuration and source it from config.nu if nushell is installed
if command -v nu &>/dev/null; then
    echo -e "\n${CYAN}[3.2/5] Updating $HOME/.config/nushell/config.nu...${RESET}"
    NUSHELL_CONFIG_DIR="$HOME/.config/nushell"
    NUSHELL_USER="$NUSHELL_CONFIG_DIR/nushell-user"
    NUSHELL_ENV="$NUSHELL_CONFIG_DIR/nushell-env"
    mkdir -p "$NUSHELL_CONFIG_DIR"
    touch "$NUSHELL_CONFIG_DIR/config.nu"
    touch "$NUSHELL_CONFIG_DIR/env.nu"

    if fetch_file "nushell-user" "$NUSHELL_USER"; then
        echo -e "  ${GREEN}✓ Updated $NUSHELL_USER${RESET}"
    fi

    if fetch_file "nushell-env" "$NUSHELL_ENV"; then
        echo -e "  ${GREEN}✓ Updated $NUSHELL_ENV${RESET}"
    fi

    # Nushell has no [[ ]] or &&, so earlier versions of this script wrote lines that
    # cannot be parsed. Remove those, then use plain `source` lines.
    for nu_file in config.nu env.nu; do
        if grep -qF '[[ -f "$HOME/.config/nushell/nushell-' "$NUSHELL_CONFIG_DIR/$nu_file"; then
            grep -vF '[[ -f "$HOME/.config/nushell/nushell-' "$NUSHELL_CONFIG_DIR/$nu_file" \
                > "$NUSHELL_CONFIG_DIR/$nu_file.tmp" || true
            cat "$NUSHELL_CONFIG_DIR/$nu_file.tmp" > "$NUSHELL_CONFIG_DIR/$nu_file"
            rm -f "$NUSHELL_CONFIG_DIR/$nu_file.tmp"
            echo -e "  ${YELLOW}Removed old bash-style source lines from $NUSHELL_CONFIG_DIR/$nu_file${RESET}"
        fi
    done

    NUSHELL_SOURCE='source ~/.config/nushell/nushell-user'
    if ! grep -qF "$NUSHELL_SOURCE" "$NUSHELL_CONFIG_DIR/config.nu"; then
        printf '\n%s\n' "$NUSHELL_SOURCE" >> "$NUSHELL_CONFIG_DIR/config.nu"
        echo -e "  ${GREEN}✓ Added the nushell-user source line to $NUSHELL_CONFIG_DIR/config.nu${RESET}"
    else
        echo -e "  ${YELLOW}The nushell-user source line already exists in $NUSHELL_CONFIG_DIR/config.nu.${RESET}"
    fi

    NUSHELL_ENV_SOURCE='source ~/.config/nushell/nushell-env'
    if ! grep -qF "$NUSHELL_ENV_SOURCE" "$NUSHELL_CONFIG_DIR/env.nu"; then
        printf '\n%s\n' "$NUSHELL_ENV_SOURCE" >> "$NUSHELL_CONFIG_DIR/env.nu"
        echo -e "  ${GREEN}✓ Added the nushell-env source line to $NUSHELL_CONFIG_DIR/env.nu${RESET}"
    else
        echo -e "  ${YELLOW}The nushell-env source line already exists in $NUSHELL_CONFIG_DIR/env.nu.${RESET}"
    fi
fi  


# 4. Deploy Conky configuration
echo -e "\n${CYAN}[4/5] Deploying Conky configuration...${RESET}"
CONKY_DIR="$HOME/.conky"
mkdir -p "$CONKY_DIR"

for filename in allcombined.lua sidebar-conkyrc topbar-conkyrc moon_info.py conky-start.sh; do
    if fetch_file "$filename" "$CONKY_DIR/$filename"; then
        echo -e "  ${GREEN}✓ Copied $filename to $CONKY_DIR/${RESET}"
    fi
done

# 4.75 Deploy Fastfetch configuration
echo -e "\n${CYAN}[4.75/5] Deploying Fastfetch configuration...${RESET}"
FASTFETCH_DIR="$HOME/.config/fastfetch"
mkdir -p "$FASTFETCH_DIR"

if fetch_file "config.jsonc" "$FASTFETCH_DIR/config.jsonc"; then
    echo -e "  ${GREEN}✓ Copied config.jsonc to $FASTFETCH_DIR/${RESET}"
fi

# 5. Run the package installation script for the detected distro
echo -e "\n${CYAN}[5/5] Package Installation Check...${RESET}"

TEMP_PACKAGE_SCRIPT=""
PACKAGE_EXEC=""
if [ -n "$PACKAGE_SCRIPT" ]; then
    if ! fetch_file "apps.list" "$LOCAL_BIN/apps.list" \
        || ! fetch_file "apps-common.sh" "$LOCAL_BIN/apps-common.sh"; then
        echo -e "${YELLOW}Could not install the shared app list and loader.${RESET}"
        exit 1
    fi

    GUI_SCRIPT=""
    case "$PACKAGE_SCRIPT" in
        debian-apt.sh) GUI_SCRIPT="guiapps-apt.sh" ;;
        fedora-dnf.sh) GUI_SCRIPT="guiapps-dnf.sh" ;;
        freebsd-pkg.sh) GUI_SCRIPT="guiapps-pkg.sh" ;;
        void-xbps.sh) GUI_SCRIPT="guiapps-xbps.sh" ;;
    esac

    if [ -n "$GUI_SCRIPT" ]; then
        if fetch_file "guiapps-common.sh" "$LOCAL_BIN/guiapps-common.sh" \
            && fetch_file "$GUI_SCRIPT" "$LOCAL_BIN/$GUI_SCRIPT" \
            && fetch_file "kitty.conf" "$LOCAL_BIN/kitty.conf"; then
            chmod +x "$LOCAL_BIN/guiapps-common.sh" "$LOCAL_BIN/$GUI_SCRIPT"
            echo -e "  ${GREEN}Installed $GUI_SCRIPT for manual use; it will not be run by setup.${RESET}"
        fi
    fi

    if fetch_file "setup-browser.sh" "$LOCAL_BIN/setup-browser.sh"; then
        chmod +x "$LOCAL_BIN/setup-browser.sh"
        echo -e "  ${GREEN}Installed setup-browser.sh for manual use; it will not be run by setup.${RESET}"
    fi

    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$PACKAGE_SCRIPT" ]; then
        PACKAGE_EXEC="$SCRIPT_DIR/$PACKAGE_SCRIPT"
    else
        TEMP_PACKAGE_SCRIPT="$(mktemp "/tmp/${PACKAGE_SCRIPT%.sh}.XXXXXX")"
        if fetch_file "$PACKAGE_SCRIPT" "$TEMP_PACKAGE_SCRIPT"; then
            PACKAGE_EXEC="$TEMP_PACKAGE_SCRIPT"
        else
            PACKAGE_EXEC=""
        fi
    fi

    if [ -n "$PACKAGE_EXEC" ]; then
        # Prompt user safely, attaching stdin to /dev/tty if stdin is piped
        PROMPT_CMD="read -p 'Would you like to run $PACKAGE_SCRIPT to update and install packages now? (y/N) ' -n 1 -r REPLY"
        if [ -c /dev/tty ]; then
            eval "$PROMPT_CMD < /dev/tty" || REPLY="N"
        else
            eval "$PROMPT_CMD" || REPLY="N"
        fi
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            bash "$PACKAGE_EXEC" "$@" \
                || echo -e "  ${YELLOW}$PACKAGE_SCRIPT did not finish cleanly; continuing.${RESET}"
        else
            echo -e "  ${YELLOW}Skipped package installation. You can run $PACKAGE_SCRIPT manually later.${RESET}"
        fi
    fi
else
    echo -e "  ${YELLOW}Unsupported or undetected operating system; skipping package installation.${RESET}"
fi

# 6. Install extra CLI tools from install-extra.sh
if fetch_file "install-extra.sh" "$LOCAL_BIN/install-extra.sh"; then
    chmod +x "$LOCAL_BIN/install-extra.sh"
    echo -e "\n${CYAN}[6/5] Installing extra CLI tools...${RESET}"
    bash "$LOCAL_BIN/install-extra.sh" \
        || echo -e "  ${YELLOW}Some extra CLI tools failed to install; continuing.${RESET}"
else
    echo -e "  ${YELLOW}Could not fetch install-extra.sh; skipping extra CLI tools installation.${RESET}"
fi 

# Cleanup downloaded installer if created
if [ -n "$TEMP_PACKAGE_SCRIPT" ] && [ -f "$TEMP_PACKAGE_SCRIPT" ]; then
    rm -f "$TEMP_PACKAGE_SCRIPT"
fi

echo -e "\n${GREEN}====================================================${RESET}"
echo -e "${GREEN}   ✨ Dotfiles setup complete! Restart terminal or run: source ~/.bashrc${RESET}"
echo -e "${GREEN}====================================================${RESET}"
