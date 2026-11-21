#!/usr/bin/env bash

set -euo pipefail

REPOSITORY="VastBlast/authenticator-2fa"
KONODE_URL="https://chromewebstore.google.com/detail/konode/mmlfiiimnpnjcjhhbldenpcmnibedkfa"
EXTENSIONS_DIR="$HOME/Applications/Extensions"

for utility in curl jq unzip sha256sum; do
    if ! command -v "$utility" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$utility" >&2
        exit 1
    fi
done

release_data="$(curl -fsSL "https://api.github.com/repos/$REPOSITORY/releases/latest")"
release_tag="$(jq -r '.tag_name // empty' <<< "$release_data")"
asset="$(jq -c --arg tag "$release_tag" '.assets[] | select(.name == ("authenticator-2fa-chrome-" + $tag + ".zip"))' <<< "$release_data")"
asset_url="$(jq -r '.browser_download_url // empty' <<< "$asset")"
asset_digest="$(jq -r '.digest // empty' <<< "$asset")"

if [[ -z "$release_tag" || -z "$asset_url" || "$asset_digest" != sha256:* ]]; then
    echo "Could not find a verifiable Chrome extension release." >&2
    exit 1
fi

extension_dir="$EXTENSIONS_DIR/authenticator-2fa-$release_tag"
mkdir -p "$EXTENSIONS_DIR"
if [[ -f "$extension_dir/manifest.json" ]]; then
    echo "Authenticator extension already unpacked: $extension_dir"
else
    if [[ -e "$extension_dir" ]]; then
        echo "Extension destination exists but is incomplete: $extension_dir" >&2
        exit 1
    fi

    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/setup-browser.XXXXXX")"
    stage_dir="$(mktemp -d "$EXTENSIONS_DIR/.authenticator-2fa.XXXXXX")"
    trap 'rm -rf "$temp_dir" "$stage_dir"' EXIT
    curl -fL "$asset_url" -o "$temp_dir/authenticator-2fa.zip"
    printf '%s  %s\n' "${asset_digest#sha256:}" "$temp_dir/authenticator-2fa.zip" | sha256sum -c -
    unzip -q "$temp_dir/authenticator-2fa.zip" -d "$stage_dir"
    if [[ ! -f "$stage_dir/manifest.json" ]]; then
        echo "Downloaded archive does not contain a root manifest.json." >&2
        exit 1
    fi
    mv "$stage_dir" "$extension_dir"
    echo "Authenticator extension unpacked to $extension_dir"
fi

browser="$(command -v helium || command -v helium-browser || true)"
if [[ -z "$browser" ]]; then
    printf 'Helium was not found. Open this page in Helium to install Konode:\n%s\n' "$KONODE_URL" >&2
    exit 1
fi

"$browser" "$KONODE_URL" >/dev/null 2>&1 &
echo "Opened Konode in Helium. Approve the extension installation in the browser."