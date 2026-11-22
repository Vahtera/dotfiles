#!/usr/bin/env bash
###############################################################################
# 🚀 Dotfiles Master Bootstrap / Setup Script (v2)
# Repo: https://github.com/Vahtera/dotfiles
###############################################################################

set -e

REPO_RAW_URL="https://raw.githubusercontent.com/Vahtera/dotfiles/main"
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"

# sshd, ufw, nft, iptables, ... live in sbin directories that a regular user's PATH
# often lacks (e.g. Debian), which makes `command -v` miss tools that are installed.
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

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

# Shared helpers (colors, fetch_file, ...). Use the clone's copy; when run via curl, download
# it first. A copy also ends up in ~/.local/bin for the setup-<shell>.sh scripts.
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/setup-common.sh" ]; then
    # shellcheck source=setup-common.sh
    source "$SCRIPT_DIR/setup-common.sh"
else
    if command -v curl &>/dev/null; then
        curl -fsSL "$REPO_RAW_URL/setup-common.sh" -o "$LOCAL_BIN/setup-common.sh" || rm -f "$LOCAL_BIN/setup-common.sh"
    elif command -v wget &>/dev/null; then
        wget -qO "$LOCAL_BIN/setup-common.sh" "$REPO_RAW_URL/setup-common.sh" || rm -f "$LOCAL_BIN/setup-common.sh"
    fi
    if [ ! -s "$LOCAL_BIN/setup-common.sh" ]; then
        echo "Error: could not get setup-common.sh (need curl or wget, and network access)." >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$LOCAL_BIN/setup-common.sh"
fi

echo -e "${CYAN}====================================================${RESET}"
echo -e "${PURPLE}   Setting up Dotfiles for user: ${YELLOW}$USER${RESET}"
echo -e "${CYAN}====================================================${RESET}\n"

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

# Small commands shared by every shell (bash, zsh and Nushell all run them as programs)
for cmd_script in kernel showip weather; do
    if fetch_file "$cmd_script.sh" "$LOCAL_BIN/$cmd_script"; then
        chmod +x "$LOCAL_BIN/$cmd_script"
        echo -e "  ${GREEN}✓ Installed $cmd_script${RESET}"
    fi
done

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

# 2. Update the shell configuration (bash, zsh, nushell). Each setup-<shell>.sh can also be
# run on its own, e.g. ~/.local/bin/setup-zsh.sh, to update just one shell.
echo -e "\n${CYAN}[2-3/5] Updating shell configuration...${RESET}"
fetch_file "setup-common.sh" "$LOCAL_BIN/setup-common.sh" || true
for shell_script in setup-bash.sh setup-zsh.sh setup-nushell.sh; do
    if fetch_file "$shell_script" "$LOCAL_BIN/$shell_script"; then
        chmod +x "$LOCAL_BIN/$shell_script"
        # From a clone, run the clone's copy so local changes are used; otherwise the installed one
        shell_script_dir="$LOCAL_BIN"
        if [ -n "$SCRIPT_DIR" ]; then
            shell_script_dir="$SCRIPT_DIR"
        fi
        bash "$shell_script_dir/$shell_script" \
            || echo -e "  ${YELLOW}$shell_script did not finish cleanly; continuing.${RESET}"
    else
        echo -e "  ${YELLOW}Could not fetch $shell_script; skipping.${RESET}"
    fi
done

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
