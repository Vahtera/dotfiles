#!/bin/bash
# This script downloads and installs the MesloLGS NF Nerd Font for use in terminal emulators.
mkdir -p "$HOME/.local/share/fonts"
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Meslo.zip
unzip Meslo.zip -d "$HOME/.local/share/fonts/"
rm Meslo.zip