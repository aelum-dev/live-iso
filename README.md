# AestheticOS

![AestheticOS](images/hero-light.png)

AestheticOS is an Arch Linux distro with a fully offline installer. The live ISO itself is intentionally barebones — its only job is to boot and launch the [AestheticOS Installer](https://gitlab.com/aestheticos/installer). That installer then sets up a complete, polished desktop: [Hyprland](https://hyprland.org/) window management, the DankMaterialShell + DMS greeter login, automatic color theming with matugen, and more.

The install itself needs no internet. Every package is cached locally in an embedded repository, so it's completely air-gapped: boot it on any machine, the installer starts on its own, and you don't need a network connection to install it. Once installed, it's a normal Arch system — use the internet, update packages, install whatever you like.

---

## Features

- **Offline install** — every package needed to install is embedded in the ISO, so the install doesn't touch the network. (Once installed, your system works like any Arch install and uses the internet normally.)
- **Auto-launching installer** — on first boot, greetd starts a barebones Hyprland that opens the installer by itself
- **Silent boot** — clean UEFI splash with the Plymouth BGRT theme (your OEM logo), no console spam
- **Auto monitor scaling** — detects the connected monitor and applies the right Hyprland scale automatically, so the installer reads crisply at 1080p, 1440p, or 4K
- **Quick install** — since every package is included, install takes about a minute and the finished OS uses roughly 4.7 GB

## What you install

The installer hands you a finished desktop, pre-configured and ready:

- **Hyprland** dynamic tiling with DankMaterialShell (Quickshell-based) for a clean, modern look
- **DMS greeter** (greetd) — a fast login screen
- **matugen** — generates matching color schemes from your wallpaper automatically
- **Alacritty**, **Firefox**, **PipeWire** audio, and a silent **Plymouth BGRT** boot splash
- **GTK + Qt apps get matugen-themed automatically**. In Qt apps, just pick the built-in matugen theme and it matches the rest of the system
- **zram** compressed swap — fast, and no disk space reserved for a swap file

## Why AestheticOS

- **Installs without a network.** No chasing slow or missing mirrors during install — everything is baked into the ISO. Handy on a machine that has no internet at install time. (After install you can connect normally.)
- **A finished desktop, not a blank slate.** You get a curated Hyprland + DMS setup with automatic theming, so it looks reasonable straight after install.
- **Quiet boot.** Silent boot with your OEM logo, auto monitor scaling, and zram instead of a swap file.
- **Nothing extra.** The live ISO exists to launch the installer, so there's little to configure or clean up.

---

## Project Structure

This repo is the **AestheticOS profile** — the content that goes into the ISO. The build pipeline that turns it into an ISO now lives in a separate repo: [aestheticos/docker](https://gitlab.com/aestheticos/docker). See [Building & Running](#building--running) below.

```
.
├── profiledef.sh          # ISO metadata (name, label, publisher, install dir)
├── packages.x86_64        # Official packages to include
├── packages.aur.x86_64    # AUR packages to build
├── bootstrap_packages     # Packages for the base install environment
├── pacman-offline.conf    # Pacman config used by mkarchiso (offline mirror only)
├── airootfs/              # Root filesystem for the ISO
│   ├── etc/
│   │   ├── greetd/            # greetd + DMS greeter config (launches installer)
│   │   ├── mkinitcpio.conf.d/ # Live ISO mkinitcpio hooks
│   │   ├── mkinitcpio.d/      # Kernel preset
│   │   ├── pacman.conf        # Installed system pacman config (offline mirror)
│   │   ├── plymouth/          # Plymouth daemon config
│   │   ├── skel/              # Default user home (dotfiles)
│   │   ├── skel/.hushlogin    # Suppress "Last login" message
│   │   ├── systemd/system/    # Systemd units (animation delay, etc.)
│   │   └── sudoers.d/         # Sudo config for aestheticos user
│   └── usr/share/DankMaterialShell/  # DMS desktop files
├── efiboot/               # systemd-boot EFI boot entries
│   └── loader/entries/
│       └── 01-aestheticos-linux.conf
├── grub/                  # GRUB (BIOS/UEFI) boot config
├── syslinux/              # Syslinux (BIOS) boot config
└── images/                # Website / README images
```

---

## Building & Running

All building (ISO creation) and running (QEMU testing) of AestheticOS are done in the [aestheticos/docker](https://gitlab.com/aestheticos/docker) repo — not here. This repo only holds the profile content that goes into the ISO. See the [docker repo README](https://gitlab.com/aestheticos/docker) for build and run instructions.

---

## Offline Install (No Internet During Install)

All packages needed for the install are cached in `airootfs/var/cache/aestheticos/offline-mirror/` and served via a `file://` URL in the ISO's pacman.conf, so the install doesn't reach the network. This applies to installation only — the installed system is a regular Arch install and uses the internet for updates and anything else you add.

Because every package is included, **installation takes about 1 minute**, and the **complete OS requires roughly 4.7 GB of disk space** after install.

---

## License

Released under the [GNU General Public License v3.0 (GPL-3.0)](https://www.gnu.org/licenses/gpl-3.0.html). See the `LICENSE` file for the full text.
