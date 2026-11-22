#!/usr/bin/env bash
# Shows the weather from wttr.in.
#   weather            uses the city your public IP maps to
#   weather Helsinki   uses the location you give
# Installed as `weather` in ~/.local/bin, so it works the same in bash, zsh and Nushell.

if ! command -v curl >/dev/null 2>&1; then
    echo "weather: curl is required." >&2
    exit 1
fi

location="$*"
if [[ -z "$location" ]]; then
    # If the lookup fails, wttr.in falls back to locating the request by IP itself.
    location="$(curl -fsS --max-time 3 'http://ip-api.com/line/?fields=city' 2>/dev/null)" || location=""
fi

exec curl "wttr.in/${location// /+}?M"
