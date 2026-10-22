#!/usr/bin/env bash
# Disable automatically learned IPv6 DNS on the active
# NetworkManager connection, while preserving IPv6 connectivity.

set -euo pipefail

if ! command -v nmcli >/dev/null 2>&1; then
    echo "Error: nmcli is not installed." >&2
    exit 1
fi

if ! nmcli general status >/dev/null 2>&1; then
    echo "Error: NetworkManager is not running or accessible." >&2
    exit 1
fi

# Find active, non-loopback connections attached to devices.
mapfile -t connections < <(
    nmcli -t --escape no -f NAME,DEVICE connection show --active |
    awk -F: '$2 != "" && $2 != "lo" {print $1}'
)

if ((${#connections[@]} == 0)); then
    echo "Error: No active NetworkManager connection found." >&2
    exit 1
fi

if ((${#connections[@]} > 1)); then
    echo "Multiple active connections found:"
    printf '  %s\n' "${connections[@]}"
    echo "Please specify which connection to configure." >&2
    exit 1
fi

connection="${connections[0]}"

echo "Active connection: $connection"
echo "Setting ipv6.ignore-auto-dns=yes..."

sudo nmcli connection modify "$connection" \
    ipv6.ignore-auto-dns yes

echo
echo "Done. IPv6 connectivity remains enabled."
echo "Reconnect the connection for the setting to take effect."
echo "Verify with: resolvectl status"
