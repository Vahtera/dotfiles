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