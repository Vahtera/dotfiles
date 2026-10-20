#!/bin/sh

killall -u $(id -nu) conky 2>/dev/null
cd "$HOME/.conky"
conky -c "$HOME/.conky/sidebar-conkyrc" &
conky -c "$HOME/.conky/topbar-conkyrc" &
exit 0
