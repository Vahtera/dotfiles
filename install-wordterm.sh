#!/bin/sh

set -eu

WORDTERM_DIR="${WORDTERM_DIR:-$HOME/wordterm}"
LOCAL_BIN="$HOME/.local/bin"

if [ -d "$WORDTERM_DIR/.git" ]; then
    git -C "$WORDTERM_DIR" pull --ff-only
else
    git clone https://github.com/Vahtera/wordterm "$WORDTERM_DIR"
fi

if [ ! -f "$WORDTERM_DIR/build.sh" ]; then
    echo "build.sh not found in $WORDTERM_DIR" >&2
    exit 1
fi

# Warn early when the installed Go is older than go.mod asks for.
check_go_version() {
    [ -f "$WORDTERM_DIR/go.mod" ] || return 0
    command -v go >/dev/null 2>&1 || return 0
    required="$(sed -n 's/^go[[:space:]]\{1,\}\([0-9][0-9.]*\).*/\1/p' "$WORDTERM_DIR/go.mod" | head -n 1)"
    have="$(go version 2>/dev/null | sed -n 's/.* go\([0-9][0-9.]*\).*/\1/p' | head -n 1)"
    [ -n "$required" ] && [ -n "$have" ] || return 0
    oldest="$(printf '%s\n%s\n' "$required" "$have" | sort -V | head -n 1)"
    if [ "$oldest" != "$required" ]; then
        echo "Warning: Wordterm's go.mod needs Go $required but Go $have is installed." >&2
        echo "Go 1.21 and newer may download the required toolchain automatically; older ones cannot." >&2
        echo "If the build below fails, install a newer Go from https://go.dev/dl/." >&2
    fi
}
check_go_version

chmod +x "$WORDTERM_DIR/build.sh"
(cd "$WORDTERM_DIR" && ./build.sh --native)

if [ ! -d "$WORDTERM_DIR/dist" ]; then
    echo "Wordterm build output directory not found: $WORDTERM_DIR/dist" >&2
    exit 1
fi

wordterm_file="$(find "$WORDTERM_DIR/dist" -type f -name 'wordterm*' -perm -u+x -print -quit)"
if [ -z "$wordterm_file" ]; then
    echo "No executable Wordterm build was found in $WORDTERM_DIR/dist" >&2
    exit 1
fi

mkdir -p "$LOCAL_BIN"
if [ -L "$LOCAL_BIN/wordterm" ]; then
    rm "$LOCAL_BIN/wordterm"
elif [ -e "$LOCAL_BIN/wordterm" ]; then
    echo "$LOCAL_BIN/wordterm already exists and is not a symlink; leaving it unchanged." >&2
    exit 1
fi
ln -s "$wordterm_file" "$LOCAL_BIN/wordterm"