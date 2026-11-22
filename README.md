>[!CAUTION]
>This is a personal setup, made for my own machines. It will automatically install OpenSSH Server and open up port 22, and it **overwrites** the managed config files listed below on every run, so all my computers end up with identical settings. Just FYI.

# 🐧 Vahtera Dotfiles & System Setup

A dynamic, automated dotfiles and benchmarking suite optimized for Linux distro-hopping on both **x86** and **ARM** hardware.

Repository: [https://github.com/Vahtera/dotfiles](https://github.com/Vahtera/dotfiles)

---

## ⚡ Quick Start

Execute via command line on a supported Arch-based, Debian-based, Fedora-based, Void Linux, FreeBSD, or Haiku installation:

```bash
git clone https://github.com/Vahtera/dotfiles.git ~/.dotfiles && cd ~/.dotfiles && ./setup.sh
```

Or via direct curl execution:
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Vahtera/dotfiles/main/setup.sh)"
```

**Requirements:** `bash`, `curl` or `wget`, and either root or `sudo`. FreeBSD does not ship bash, so run `pkg install bash` first. Debian-based systems without `sudo` need to run the scripts as root.

---

## 🛠️ What `setup.sh` does

1. **Detects the distro** and sets up the SSH server first (installs OpenSSH, enables the service, opens port 22 in the firewall), so remote access works even if a later step fails. Skipped on Haiku.
2. Installs helper scripts and the Oh My Posh theme, and, if NetworkManager is running, offers to disable automatically learned IPv6 DNS (`disable-ipv6-auto-dns.sh`).
3. Downloads the Nerd Fonts listed in `install-nerdfont.sh`.
4. Updates the shell configuration by running `setup-bash.sh` (including installing [ble.sh](https://github.com/akinomyoga/ble.sh)), `setup-zsh.sh` and `setup-nushell.sh`. Each of them can also be run on its own to update just one shell (see below).
5. Deploys the Conky and Fastfetch configuration.
6. Runs the package installer for the detected distro, then installs extra CLI tools from upstream installers (`install-extra.sh`).

A failing step prints a warning and the setup carries on with the next one.

### Managed files (overwritten on every run)

`~/.bash_aliases`, Nushell `aliases.nu`, `~/.config/ohmyposh/anna.omp.json`, `~/.config/fastfetch/config.jsonc`, everything in `~/.conky/`, and the scripts in `~/.local/bin/`. The shell configs (`~/.bashrc`, `~/.zshrc`, Nushell `config.nu`/`env.nu`) are only extended with a line that sources the managed `bashrc-user`, `zshrc-user`, `nushell-user` and `nushell-env` files, so anything else in them is left alone.

---

## 📁 Included Files

### Installers

* `setup.sh` - Master installer, described above.
* `setup-common.sh` - Helpers shared by `setup.sh` and the shell scripts below (colors, `fetch_file`, source-line handling).
* `setup-bash.sh`, `setup-zsh.sh`, `setup-nushell.sh` - Update one shell's managed configuration (and, for bash and zsh, `~/.bash_aliases`; for Nushell, `aliases.nu`). `setup.sh` installs them to `~/.local/bin/`, so a single shell can be refreshed later with e.g. `~/.local/bin/setup-zsh.sh` without running the whole setup. A script skips itself when its shell is not installed. When run from a clone it uses the clone's files; otherwise it downloads the latest from GitHub.
* `apps.list` - Shared CLI package list used by all package installers. Each quoted line is one app; comma-separated names are tried in order, selecting the first available package. Python apps for pipx are listed separately.
* `apps-common.sh` - Shared loader and ordered-alternative parser for `apps.list`, plus the flatpak check and the Wordterm hook.
* `debian-apt.sh`, `fedora-dnf.sh`, `arch-pacman.sh`, `void-xbps.sh`, `freebsd-pkg.sh`, `haiku-pkgman.sh` - Package installers for each family. All of them ask before each step; pass `--auto-yes` to answer yes to everything. The Debian installer also refreshes empty package lists on its own, and it needs `sudo` unless run as root.
* `install-extra.sh` - CLI tools that come from upstream installer scripts rather than distro packages (croc, superfile, concord, Oh My Posh).
* `install-nerdfont.sh` - Installs the Nerd Fonts listed at the top of the script into `~/.local/share/fonts/NerdFonts/`. To add a font, add its archive name to the list; to remove one, delete it from the list and run the script with `--prune`. Re-runs skip fonts that are already up to date.
* `install-wordterm.sh` - Builds Wordterm from source and links it into `~/.local/bin/`. Runs after Go has been installed, or when Go exists but Wordterm does not (it asks first in that case). Warns when the installed Go is older than Wordterm's `go.mod` asks for.
* `guiapps-*.sh` - Manual GUI app installers for supported systems. `setup.sh` installs the matching script and its helper, but never runs it. Start it with `guiapps-apt.sh`, `guiapps-dnf.sh`, `guiapps-xbps.sh`, or `guiapps-pkg.sh` from `~/.local/bin/`.
* `guiapps-common.sh` - Shared GUI app installation logic, including Flatpak/Flathub setup and Kitty configuration. Downloads that GitHub publishes a SHA-256 for are verified before installing.
* `setup-browser.sh` - Manually downloads and unpacks the latest Chrome build of Authenticator - 2FA, then opens the Konode Chrome Web Store listing in Helium for approval. `setup.sh` installs this helper but never runs it; run it later with `~/.local/bin/setup-browser.sh`.
* `disable-ipv6-auto-dns.sh` - Sets `ipv6.ignore-auto-dns` on NetworkManager connections. With no arguments it configures every active Ethernet and Wi-Fi connection; pass connection names to configure only those.

### Shell configuration

* `bashrc-user`, `zshrc-user` - Managed shell configuration (PATH, zoxide, Oh My Posh prompt, welcome banner). Bash also loads ble.sh for line editing.
* `nushell-user`, `nushell-env`, `aliases.nu` - The Nushell equivalents.
* `bash_aliases` - Custom CLI shortcuts dynamically configured to your installed tools.
* `anna.omp.json` - Oh My Posh theme shared by all shells.
* `kitty.conf` - Kitty terminal configuration, installed by the GUI app installer.
* `config.jsonc` - Fastfetch configuration.

### Extras

* `welcome_banner.sh` - Interactive login greeting script displaying system stats, IP address, and weather. City, weather and public IP lookups are cached in `~/.cache/dotfiles/`, so opening a shell does not make a network request every time.
* `sidebar-conkyrc`, `topbar-conkyrc`, `allcombined.lua`, `conky-start.sh`, `moon_info.py` - Conky desktop widgets and the moon-phase helper they use.
* `run_benchmark.sh` - Multi-core & single-core CPU benchmarking tool powered by `sysbench`.
* `kernel.sh`, `showip.sh`, `weather.sh` - Small commands installed as `kernel`, `showip` and `weather` in `~/.local/bin/`. They are scripts rather than aliases so bash, zsh and Nushell all share one definition. `weather` takes an optional location (`weather Helsinki`).
