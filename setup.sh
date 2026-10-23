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

echo -e "${CYAN}====================================================${RESET}"
echo -e "${PURPLE}   Setting up Dotfiles for user: ${YELLOW}$USER${RESET}"
echo -e "${CYAN}====================================================${RESET}\n"

# Determine directory if running from a local clone
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )"

LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

# Helper function to fetch files locally or from GitHub raw URL
fetch_file() {
    local filename="$1"
    local dest="$2"

    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$filename" ]; then
        cp "$SCRIPT_DIR/$filename" "$dest"
        return 0
    elif command -v curl &>/dev/null; then
        curl -fsSL "$REPO_RAW_URL/$filename" -o "$dest"
        return 0
    elif command -v wget &>/dev/null; then
        wget -qO "$dest" "$REPO_RAW_URL/$filename"
        return 0
    else
        echo -e "${YELLOW}❌ Error: Could not locate $filename locally nor via curl/wget.${RESET}"
        return 1
    fi
}

run_privileged() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
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
    if ! nft list chain "$family" filter input >/dev/null 2>&1; then
        return 1
    fi
    if ! nft list chain "$family" filter input 2>/dev/null | grep -Eq 'tcp dport 22 accept'; then
        run_privileged nft insert rule "$family" filter input tcp dport 22 accept
    fi
}

setup_ssh_server() {
    local ssh_package="openssh-server"
    local ssh_service="sshd"

    case "$PACKAGE_SCRIPT" in
        debian-apt.sh) ssh_service="ssh" ;;
        void-xbps.sh) ssh_package="openssh" ;;
        freebsd-pkg.sh) ssh_package="openssh" ;;
    esac

    if ! command -v sshd >/dev/null 2>&1; then
        echo -e "${CYAN}Installing SSH server ($ssh_package)...${RESET}"
        case "$PACKAGE_SCRIPT" in
            debian-apt.sh) run_privileged apt install -y "$ssh_package" ;;
            fedora-dnf.sh) run_privileged dnf install -y "$ssh_package" ;;
            void-xbps.sh) run_privileged xbps-install -y "$ssh_package" ;;
            freebsd-pkg.sh) run_privileged pkg install -y "$ssh_package" ;;
        esac
    fi

    if ! command -v sshd >/dev/null 2>&1; then
        echo -e "${YELLOW}SSH server is unavailable; skipping service and firewall setup.${RESET}"
        return
    fi
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

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
        run_privileged ufw allow 22/tcp
        echo -e "${GREEN}Allowed SSH through UFW (TCP port 22).${RESET}"
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        if ! firewall-cmd --query-service=ssh >/dev/null 2>&1; then
            run_privileged firewall-cmd --permanent --add-service=ssh
            run_privileged firewall-cmd --reload
        fi
        echo -e "${GREEN}Allowed SSH through firewalld (TCP port 22).${RESET}"
    elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -Eq 'hook input'; then
        if allow_ssh_nft_chain inet || allow_ssh_nft_chain ip || allow_ssh_nft_chain ip6; then
            echo -e "${GREEN}Allowed SSH through nftables for the current ruleset (TCP port 22).${RESET}"
            echo -e "${YELLOW}Persist the rule in your nftables configuration if your rules are reloaded at boot.${RESET}"
        else
            echo -e "${YELLOW}An nftables firewall is active, but no standard filter input chain was found; allow inbound TCP port 22 in your nftables rules.${RESET}"
        fi
    elif command -v iptables >/dev/null 2>&1 && iptables -S INPUT 2>/dev/null | grep -Eq '^-P INPUT (DROP|REJECT)|^-A INPUT'; then
        if ! iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null; then
            run_privileged iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
        fi
        if command -v ip6tables >/dev/null 2>&1 && ip6tables -S INPUT 2>/dev/null | grep -Eq '^-P INPUT (DROP|REJECT)|^-A INPUT'; then
            if ! ip6tables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null; then
                run_privileged ip6tables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
            fi
        fi
        if command -v netfilter-persistent >/dev/null 2>&1; then
            run_privileged netfilter-persistent save
        else
            echo -e "${YELLOW}Allowed SSH through iptables for this session; no persistent iptables save tool was found.${RESET}"
        fi
    elif command -v ipfw >/dev/null 2>&1 && ipfw list 2>/dev/null | grep -q 'deny ip from any to any'; then
        local ipfw_rules rule_number
        ipfw_rules="$(ipfw list 2>/dev/null)"
        if ! grep -Eq 'allow tcp .*dst-port 22' <<< "$ipfw_rules"; then
            rule_number=65534
            while grep -q "^$rule_number " <<< "$ipfw_rules" && [ "$rule_number" -gt 1 ]; do
                rule_number=$((rule_number - 1))
            done
            run_privileged ipfw add "$rule_number" allow tcp from any to me 22 in
        fi
        echo -e "${GREEN}Allowed SSH through ipfw for the current ruleset (TCP port 22).${RESET}"
        echo -e "${YELLOW}Persist the rule in your FreeBSD firewall configuration if rules are reloaded at boot.${RESET}"
    elif command -v pfctl >/dev/null 2>&1 && pfctl -s info 2>/dev/null | grep -q 'Status: Enabled'; then
        echo -e "${YELLOW}PF is active. Its rules were left unchanged; allow inbound TCP port 22 in /etc/pf.conf.${RESET}"
    else
        echo -e "${CYAN}No active supported firewall detected; no firewall rules changed.${RESET}"
    fi
}

# 1. Install CLI tools to $HOME/.local/bin
echo -e "${CYAN}[1/5] Installing CLI tools to $LOCAL_BIN...${RESET}"

if fetch_file "welcome_banner.sh" "$LOCAL_BIN/welcome_banner.sh"; then
    chmod +x "$LOCAL_BIN/welcome_banner.sh"
    echo -e "  ${GREEN}✓ Installed welcome_banner.sh${RESET}"
fi

if fetch_file "run_benchmark.sh" "$LOCAL_BIN/run_benchmark.sh"; then
    chmod +x "$LOCAL_BIN/run_benchmark.sh"
    echo -e "  ${GREEN}✓ Installed run_benchmark.sh${RESET}"
fi

if [ -c /dev/tty ]; then
    read -r -p 'Disable automatically learned IPv6 DNS? (Y/n) ' REPLY < /dev/tty || REPLY=""
else
    read -r -p 'Disable automatically learned IPv6 DNS? (Y/n) ' REPLY || REPLY=""
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

# 2. Deploy .bash_aliases
echo -e "\n${CYAN}[2/5] Deploying .bash_aliases...${RESET}"
if fetch_file "bash_aliases" "$HOME/.bash_aliases"; then
    echo -e "  ${GREEN}✓ Copied .bash_aliases to $HOME/.bash_aliases${RESET}"
fi

# 3. Update .bashrc safely
echo -e "\n${CYAN}[3/5] Updating $HOME/.bashrc...${RESET}"
BASHRC="$HOME/.bashrc"
touch "$BASHRC"

MARKER="# --- Vahtera Dotfiles Configuration ---"

if grep -qF "$MARKER" "$BASHRC"; then
    echo -e "  ${YELLOW}⚠ Dotfiles configuration already exists in $BASHRC (skipping duplicate append).${RESET}"
else
    cat << 'EOF' >> "$BASHRC"

# --- Vahtera Dotfiles Configuration ---
# Ensure local bin is in PATH dynamically for active user
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$PATH:$HOME/.local/bin"
fi

# Initialize thefuck if installed
if command -v thefuck &>/dev/null; then
    eval "$(thefuck --alias)"
fi

# Initialize Homebrew if installed
if [ -d "/home/linuxbrew/.linuxbrew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Run Welcome Banner on terminal launch
if [ -x "$HOME/.local/bin/welcome_banner.sh" ] && [[ $- == *i* ]]; then
    clear && "$HOME/.local/bin/welcome_banner.sh"
fi
# --------------------------------------
EOF
    echo -e "  ${GREEN}✓ Appended custom setup block to $BASHRC${RESET}"
fi

# 4. Deploy Conky configuration
echo -e "\n${CYAN}[4/5] Deploying Conky configuration...${RESET}"
CONKY_DIR="$HOME/.conky"
mkdir -p "$CONKY_DIR"

for filename in sidebar-conkyrc topbar-conkyrc moon_info.py conky-start.sh; do
    if fetch_file "$filename" "$CONKY_DIR/$filename"; then
        echo -e "  ${GREEN}✓ Copied $filename to $CONKY_DIR/${RESET}"
    fi
done

# 5. Run the package installation script for the detected distro
echo -e "\n${CYAN}[5/5] Package Installation Check...${RESET}"

PACKAGE_SCRIPT=""
if [ -r "$OS_RELEASE_FILE" ]; then
    . "$OS_RELEASE_FILE"
    DISTRO_ID="${ID,,}"
    DISTRO_LIKE=" ${ID_LIKE,,} "

    case "$DISTRO_ID" in
        debian|ubuntu|linuxmint|pop|raspbian|kali) PACKAGE_SCRIPT="debian-apt.sh" ;;
        fedora|rhel|centos|rocky|almalinux|nobara) PACKAGE_SCRIPT="fedora-dnf.sh" ;;
        freebsd) PACKAGE_SCRIPT="freebsd-pkg.sh" ;;
        void) PACKAGE_SCRIPT="void-xbps.sh" ;;
        haiku) PACKAGE_SCRIPT="haiku-pkgman.sh" ;;
        *)
            case "$DISTRO_LIKE" in
                *" debian "*|*" ubuntu "*) PACKAGE_SCRIPT="debian-apt.sh" ;;
                *" fedora "*|*" rhel "*|*" centos "*) PACKAGE_SCRIPT="fedora-dnf.sh" ;;
            esac
            ;;
    esac
fi

if [[ "$(uname -s)" == "Haiku" ]]; then
    PACKAGE_SCRIPT="haiku-pkgman.sh"
fi

TEMP_PACKAGE_SCRIPT=""
PACKAGE_EXEC=""
if [ -n "$PACKAGE_SCRIPT" ]; then
    if [ "$PACKAGE_SCRIPT" != "haiku-pkgman.sh" ]; then
        setup_ssh_server
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
            && fetch_file "$GUI_SCRIPT" "$LOCAL_BIN/$GUI_SCRIPT"; then
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
            bash "$PACKAGE_EXEC" "$@"
        else
            echo -e "  ${YELLOW}Skipped package installation. You can run $PACKAGE_SCRIPT manually later.${RESET}"
        fi
    fi
else
    echo -e "  ${YELLOW}Unsupported or undetected operating system; skipping package installation.${RESET}"
fi

# Cleanup downloaded installer if created
if [ -n "$TEMP_PACKAGE_SCRIPT" ] && [ -f "$TEMP_PACKAGE_SCRIPT" ]; then
    rm -f "$TEMP_PACKAGE_SCRIPT"
fi

echo -e "\n${GREEN}====================================================${RESET}"
echo -e "${GREEN}   ✨ Dotfiles setup complete! Restart terminal or run: source ~/.bashrc${RESET}"
echo -e "${GREEN}====================================================${RESET}"
