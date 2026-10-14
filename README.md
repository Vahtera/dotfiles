# 🐧 Vahtera Dotfiles & System Setup

A dynamic, automated dotfiles and benchmarking suite optimized for Linux distro-hopping on both **x86** and **ARM** hardware.

Repository: [https://github.com/Vahtera/dotfiles](https://github.com/Vahtera/dotfiles)

---

## ⚡ Quick Start

Execute via command line on a supported Debian-based, Fedora-based, or Void Linux installation:

```bash
git clone https://github.com/Vahtera/dotfiles.git ~/.dotfiles && cd ~/.dotfiles && ./setup.sh
```

Or via direct curl execution:
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Vahtera/dotfiles/main/setup.sh)"
```

---

## 📁 Included Files

* `setup.sh` - Master installer. Configures `~/.bashrc`, places executables in `~/.local/bin/`, deploys `.bash_aliases`, and triggers package installation.
* `debian-apt.sh` - APT & pipx package installer featuring smart fallback handling for package alternatives (`eza`/`exa`, `fastfetch`/`neofetch`).
* `fedora-dnf.sh` - DNF package installer for Fedora and related distributions.
* `void-xbps.sh` - XBPS package installer for Void Linux.
* `welcome_banner.sh` - Interactive login greeting script displaying system stats, IP address, and weather.
* `run_benchmark.sh` - Multi-core & single-core CPU benchmarking tool powered by `sysbench`.
* `.bash_aliases` - Custom CLI shortcuts dynamically configured to your installed tools.
