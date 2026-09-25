#!/usr/bin/env bash
######################################################################
# 🌞 Welcome Banner                                                  #
######################################################################
# Prints personal greeting, system info and data about today         #
# Intended for use as a MOTD, for when using multiple systems        #
# For docs and more info, see: https://github.com/lissy93/dotfiles   #
#                                                                    #
# Licensed under MIT (C) Alicia Sykes 2022 <https://aliciasykes.com> #
######################################################################
# Modified for personalized use Anna Vahtera 2025-2026 under MIT     #
######################################################################

COLOR_P='\033[1;36m'
COLOR_S='\033[0;36m'
RESET='\033[0m'

welcome_greeting () {
    local h
    h=$(date +%H)
    h=$((10#$h))

    if [ $h -lt 4 ] || [ $h -gt 22 ]; then
        greeting="Good night"
    elif [ $h -lt 12 ]; then
        greeting="Good morning"
    elif [ $h -lt 18 ]; then
        greeting="Good afternoon"
    elif [ $h -lt 22 ]; then
        greeting="Good evening"
    else
        greeting="Hello"
    fi

    WELCOME_MSG="$greeting ${USER}!"

    if command -v lolcat &>/dev/null && command -v figlet &>/dev/null; then
        echo "${WELCOME_MSG}" | figlet | lolcat
    else
        echo -e "${COLOR_P}${WELCOME_MSG}${RESET}\n"
    fi
}

welcome_sysinfo () {
    if command -v fastfetch &>/dev/null; then
        fastfetch
    elif command -v neofetch &>/dev/null; then
        neofetch
    else
        echo -e "${COLOR_S}System: $(uname -sr) on $(uname -m)${RESET}"
    fi
}

welcome_today () {
    local timeout=2
    echo -e "\033[1;34mToday\n------${RESET}"

    local last_login
    last_login=$(last 2>/dev/null | grep "^$USER " | head -1 | awk '{print "⏲️  Last Login: "$4" "$5" "$6" "$7" on "$2}')
    if [ -n "$last_login" ]; then
        echo -e "${COLOR_S}${last_login}${RESET}"
    fi

    echo -e "${COLOR_S}$(date '+🗓️  Date: %A, %B %d, %Y at %H:%M')${RESET}"

    if command -v curl &>/dev/null; then
        local weather
        weather=$(curl -s -m $timeout "https://wttr.in/?format=%c%l:+%C+%t,+%p+%w&M" 2>/dev/null)
        if [ -n "$weather" ]; then
            echo -e "${COLOR_S}🌤️  Weather: ${weather}${RESET}"
        fi
    fi

    if command -v ip &>/dev/null; then
        local ip_address ip_interface public_ip
        ip_address=$(ip route get 8.8.8.8 2>/dev/null | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
        ip_interface=$(ip route get 8.8.8.8 2>/dev/null | awk -F"dev " 'NR==1{split($2,a," ");print a[1]}')
        public_ip=$(curl -s -m $timeout 'https://ipinfo.io/ip' 2>/dev/null)

        if [ -n "$ip_address" ]; then
            echo -e "${COLOR_S}🌐 IP: ${public_ip:-N/A} (${ip_address} on ${ip_interface})${RESET}\n"
        fi
    fi
}

welcome() {
    welcome_greeting
    welcome_sysinfo
    welcome_today
}

welcome "$@"
