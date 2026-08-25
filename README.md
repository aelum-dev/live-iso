# AestheticOS

![AestheticOS](images/hero-light.png)

AestheticOS is an Arch Linux distro with a fully offline installer. The live ISO itself is intentionally barebones — its only job is to boot and launch the [AestheticOS Installer](https://github.com/KornienkoDev/AestheticOS-Installer). That installer then sets up a complete, polished desktop: [Hyprland](https://hyprland.org/) window management, the DankMaterialShell + DMS greeter login, automatic color theming with matugen, and more.

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

```
.
├── profiledef.sh          # ISO metadata (name, label, publisher, install dir)
├── packages.x86_64        # Official packages to include
├── packages.aur.x86_64    # AUR packages to build
├── pacman.conf            # Pacman config for the build environment
├── run.sh                 # QEMU launch script for testing
├── OVMF_VARS.fd           # UEFI variables for QEMU
├── airootfs/              # Root filesystem for the ISO
│   ├── etc/
│   │   ├── greetd/            # greetd + DMS greeter config (launches installer)
│   │   ├── mkinitcpio.conf.d/ # Live ISO mkinitcpio hooks
│   │   ├── mkinitcpio.d/      # Kernel preset
│   │   ├── pacman.d/hooks/    # Pacman hooks (e.g. plymouth theme setup)
│   │   ├── plymouth/          # Plymouth daemon config
│   │   ├── skel/              # Default user home (dotfiles)
│   │   ├── skel/.hushlogin    # Suppress "Last login" message
│   │   ├── systemd/system/    # Systemd units (animation delay, etc.)
│   │   └── sudoers.d/         # Sudo config for aestheticos user
│   └── usr/share/plymouth/themes/  # Plymouth themes
├── efiboot/               # systemd-boot EFI boot entries
│   └── loader/entries/
│       └── 01-aestheticos-linux.conf
├── docker/                # Docker Compose build pipeline
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── build-scripts/     # Pipeline step scripts
├── build/                 # Native build pipeline scripts (fallback)
│   ├── 01_download_packages.sh   # Download official packages
│   ├── 02_download_aur.sh        # Resolve + download AUR PKGBUILDs
│   ├── 03_build_aur.sh           # Compile AUR packages
│   ├── 04_create_repository.sh   # Create offline mirror
│   └── 05_build_iso.sh           # Run mkarchiso to build the ISO
├── downloads/
│   ├── official_packages/     # Downloaded .pkg.tar.zst files
│   ├── aur_packages/          # Built AUR .pkg.tar.zst files
│   └── aur_build/             # AUR PKGBUILD source dirs
├── output/                  # Built ISO files
├── work/                    # mkarchiso working directory (cleaned each build)
└── vdisk.qcow2              # QEMU virtual disk for testing
```

---

## Test with QEMU

```bash
bash run.sh
```

Launches the latest ISO in QEMU with:
- KVM acceleration
- 4 cores, 4GB RAM
- VirtIO GPU with GL (virgl)
- OVMF UEFI firmware
- Shared directory mount
- User-mode networking (SSH forwarded to port 2222)

---

## Key Configuration

### Silent Boot

Kernel parameters in `efiboot/loader/entries/01-aestheticos-linux.conf`:

```
quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0
```

- `quiet` — suppress kernel messages
- `splash` — show Plymouth (required alongside `quiet`)
- `loglevel=3` — reduce console verbosity
- `rd.udev.log_level=3` — silence initramfs udev messages
- `vt.global_cursor_default=0` — hide cursor blinking

### Plymouth BGRT Theme

- Theme: `bgrt` (built-in, reads UEFI firmware logo at runtime)
- Config: `airootfs/etc/plymouth/plymouthd.conf`
- Hook: `plymouth` added to mkinitcpio HOOKS in `airootfs/etc/mkinitcpio.conf.d/archiso.conf`
- The pacman hook at `airootfs/etc/pacman.d/hooks/90-plymouth-theme.hook` auto-runs `plymouth-set-default-theme -R bgrt` after plymouth install

### Offline Install (No Internet During Install)

All packages needed for the install are cached in `airootfs/var/cache/aestheticos/offline-mirror/` and served via a `file://` URL in the ISO's pacman.conf, so the install doesn't reach the network. This applies to installation only — the installed system is a regular Arch install and uses the internet for updates and anything else you add.

Because every package is included, **installation takes about 1 minute**, and the **complete OS requires roughly 4.7 GB of disk space** after install.

---

## Requirements

### Docker (Recommended)

- Docker + Docker Compose
- ~15 GB of free disk space for the build and the ~4.7 GB installed OS

### Native Build

- `archiso` package (for `mkarchiso`)
- `edk2-ovmf` (for QEMU testing)
- `qemu` with KVM support
- An AUR helper (`yay` or similar)
- Root/sudo for package download and ISO build
- ~15 GB of free disk space for the build and the ~4.7 GB installed OS

---

## License

See individual package licenses. This ISO project itself is released under the same license as the Arch Linux packages it bundles.
