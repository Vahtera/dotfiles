# 🐧 Vahtera Dotfiles & System Setup

A dynamic, automated dotfiles and benchmarking suite optimized for Linux distro-hopping on both **x86** and **ARM** hardware.

Repository: [https://github.com/Vahtera/dotfiles](https://github.com/Vahtera/dotfiles)

---

## ⚡ Quick Start

Execute via command line on any fresh Debian/Ubuntu installation:

```bash
git clone https://github.com/Vahtera/dotfiles.git ~/.dotfiles && cd ~/.dotfiles && ./setup.sh
```

Or via direct curl execution:
```bash
curl -sSL https://raw.githubusercontent.com/Vahtera/dotfiles/main/setup.sh | bash
```

---

## 📁 Included Files

* `setup.sh` - Master installer. Configures `~/.bashrc`, places executables in `~/.local/bin/`, deploys `.bash_aliases`, and triggers package installation.
* `debian-apt.sh` - APT & pipx package installer featuring smart fallback handling for package alternatives (`eza`/`exa`, `fastfetch`/`neofetch`).
* `welcome_banner.sh` - Interactive login greeting script displaying system stats, IP address, and weather.
* `run_benchmark.sh` - Multi-core & single-core CPU benchmarking tool powered by `sysbench`.
* `.bash_aliases` - Custom CLI shortcuts dynamically configured to your installed tools.
