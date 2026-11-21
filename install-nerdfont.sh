#!/usr/bin/env bash
# Installs Nerd Fonts listed in NERD_FONTS into ~/.local/share/fonts/NerdFonts/<name>/
# Add a font: add its archive name below (the .zip names on the Nerd Fonts releases page).
# Remove a font: delete it from the list and run with --prune.
set -uo pipefail

NF_VERSION="v3.5.1"
NERD_FONTS=(
  Meslo
  FiraMono
  Terminus
  OpenDyslexic
)

FONT_ROOT="$HOME/.local/share/fonts/NerdFonts"
BASE_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/$NF_VERSION"

for cmd in curl unzip; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd is required." >&2; exit 1; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
changed=0
failed=()

mkdir -p "$FONT_ROOT"

# Checksums are optional: verify if the release provides them
curl -fsSL "$BASE_URL/SHA-256.txt" -o "$tmp/SHA-256.txt" 2>/dev/null \
  || echo "Warning: no checksum file found, skipping verification." >&2

install_font() {
  local name="$1" dir="$FONT_ROOT/$1" zip="$tmp/$1.zip" expected actual

  if [[ "$(cat "$dir/.version" 2>/dev/null)" == "$NF_VERSION" ]]; then
    echo "[Skipping] $name $NF_VERSION is already installed"
    return 0
  fi

  echo "[Installing] $name $NF_VERSION"
  curl -fL "$BASE_URL/$name.zip" -o "$zip" || return 1

  if [[ -s "$tmp/SHA-256.txt" ]]; then
    expected="$(awk -v f="$name.zip" '$2 == f { print $1 }' "$tmp/SHA-256.txt")"
    if [[ -n "$expected" ]]; then
      actual="$(sha256sum "$zip" | cut -d' ' -f1)"
      [[ "$expected" == "$actual" ]] || { echo "Checksum mismatch for $name" >&2; return 1; }
    fi
  fi

  rm -rf "$dir" && mkdir -p "$dir"
  unzip -qo "$zip" -d "$dir" || return 1
  echo "$NF_VERSION" > "$dir/.version"
  changed=1
}

# Remove installed fonts that are no longer in the list
if [[ "${1:-}" == "--prune" ]]; then
  for dir in "$FONT_ROOT"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    if [[ " ${NERD_FONTS[*]} " != *" $name "* ]]; then
      echo "[Removing] $name"
      rm -rf "$dir"
      changed=1
    fi
  done
fi

for font in "${NERD_FONTS[@]}"; do
  install_font "$font" || { echo "Failed to install $font" >&2; failed+=("$font"); }
done

if [[ "$changed" -eq 1 ]] && command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f "$FONT_ROOT"
fi

if ((${#failed[@]})); then
  echo "Fonts not installed: ${failed[*]}" >&2
  exit 1
fi
echo "Fonts up to date."