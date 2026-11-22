#!/usr/bin/env bash
# Disable automatically learned IPv6 DNS on NetworkManager connections, while
# preserving IPv6 connectivity.
#
# Usage: disable-ipv6-auto-dns.sh [CONNECTION_NAME ...]
#   With no arguments every active Ethernet and Wi-Fi connection is configured.
#   With arguments only the named connections are configured.

set -euo pipefail

if ! command -v nmcli >/dev/null 2>&1; then
    echo "Error: nmcli is not installed." >&2
    exit 1
fi

if ! nmcli general status >/dev/null 2>&1; then
    echo "Error: NetworkManager is not running or accessible." >&2
    exit 1
fi

if (($# > 0)); then
    connections=("$@")
else
    # Active Ethernet and Wi-Fi connections attached to a device. NAME is the last field
    # so that names containing ':' survive the split.
    mapfile -t connections < <(
        nmcli -t --escape no -f TYPE,DEVICE,NAME connection show --active |
        awk -F: '($1 == "802-3-ethernet" || $1 == "802-11-wireless") && $2 != "" {
            sub(/^[^:]*:[^:]*:/, ""); print
        }'
    )
fi

if ((${#connections[@]} == 0)); then
    echo "Error: No active Ethernet or Wi-Fi NetworkManager connection found." >&2
    echo "You can name a connection explicitly: $0 \"Connection name\"" >&2
    exit 1
fi

sudo_cmd=()
if [[ "$EUID" -ne 0 ]]; then
    sudo_cmd=(sudo)
fi

failed=0
for connection in "${connections[@]}"; do
    echo "Connection: $connection"
    echo "  Setting ipv6.ignore-auto-dns=yes..."
    if ! "${sudo_cmd[@]}" nmcli connection modify "$connection" ipv6.ignore-auto-dns yes; then
        echo "  Failed to modify '$connection'." >&2
        failed=1
    fi
done

echo
if ((failed)); then
    echo "Some connections could not be configured." >&2
    exit 1
fi
echo "Done. IPv6 connectivity remains enabled."
echo "Reconnect the connection(s) for the setting to take effect."
echo "Verify with: resolvectl status"
