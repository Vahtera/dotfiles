#!/usr/bin/env bash

APPS_COMMON_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APPS_FILE="$APPS_COMMON_DIR/apps.list"
if [[ ! -r "$APPS_FILE" ]]; then
    APPS_FILE="$HOME/.local/bin/apps.list"
fi
if [[ ! -r "$APPS_FILE" ]]; then
    echo "Could not find apps.list next to apps-common.sh or in ~/.local/bin." >&2
    return 1
fi
source "$APPS_FILE"

parse_app_alternatives() {
    local part
    local -a parsed=()
    IFS=',' read -r -a parsed <<< "$1"
    APP_ALTERNATIVES=()
    for part in "${parsed[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        [[ -n "$part" ]] && APP_ALTERNATIVES+=("$part")
    done
}

select_available_app() {
    local availability_check="$1" candidate
    local app_line="$2"
    parse_app_alternatives "$app_line"
    APP_SELECTED=""
    for candidate in "${APP_ALTERNATIVES[@]}"; do
        if "$availability_check" "$candidate"; then
            APP_SELECTED="$candidate"
            return 0
        fi
    done
    return 1
}