# AestheticOS

<img width="2560" height="1440" alt="hero-light" src="https://github.com/user-attachments/assets/fcde5aa1-079c-4400-980d-fa44bf509539" />

AestheticOS is a beautiful, fully offline Arch Linux distro. The live ISO itself is intentionally barebones — its only job is to boot and launch the [AestheticOS Installer](https://github.com/KornienkoDev/AestheticOS-Installer). But that installer installs a complete, polished desktop: [Hyprland](https://hyprland.org/) window management, the DankMaterialShell + DMS greeter login, automatic color theming with matugen, and more — ready to use the moment install finishes.

**No internet required — ever.** Every package is cached locally in an embedded repository, so the whole process is completely air-gapped: boot it on any machine, the installer starts on its own, and you never need a network connection — not during install, not after.

---

## Features

- **Fully offline** — every package is embedded in the ISO; zero network dependency, ever
- **Zero-touch boot** — greetd launches barebones hyprland and then it starts the installer automatically on first boot
- **Silent boot** — clean UEFI splash with the Plymouth BGRT theme (your OEM logo), no console spam
- **Auto monitor scaling** — detects the connected monitor and applies the right Hyprland scale automatically, so the installer is crisp on any resolution (1080p / 1440p / 4K)
- **Fast & lightweight install** — since every package is included, install takes ~1 minute and the full OS uses ~4.7 GB after install

## What you install

The installer hands you a finished desktop, pre-configured and ready:

- **Hyprland** dynamic tiling with DankMaterialShell (Quickshell-based) for a clean, modern look
- **DMS greeter** (greetd) — fast, elegant login screen
- **matugen** — generates matching color schemes from your wallpaper automatically
- **Alacritty**, **Firefox**, **PipeWire** audio, and a silent **Plymouth BGRT** boot splash
- **GTK + Qt apps are matugen-themed out of the box** — zero configuration required. In Qt apps, just pick the built-in matugen theme and it matches every color in the rest of the system
- **zram** compressed swap — fast, and no disk space reserved for a swap file

## Why AestheticOS

- **Installs offline, runs anywhere.** No flaky mirror fetches or missing packages during install — everything is baked into the ISO. Works on a machine with no internet at all.
- **Beautiful out of the box.** Not a bare Arch you theme yourself. You get a curated Hyprland + DMS setup with automatic theming, so it looks great on the first boot after install.
- **Fast and quiet.** Silent boot with your OEM logo, auto monitor scaling, and zram instead of a slow swap file.
- **Zero surprises.** A minimal, intentional live ISO that does exactly one thing — launch the installer — so there's nothing extra to configure or clean up.

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
├── build/                 # Build pipeline scripts
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

## Build Pipeline

Run the build scripts in order (as root where needed):

```bash
# 1. Download official packages
sudo bash build/01_download_packages.sh

# 2. Download AUR PKGBUILDs (resolves deps via AUR API)
bash build/02_download_aur.sh

# 3. Build AUR packages
bash build/03_build_aur.sh

# 4. Create the offline mirror repository
sudo bash build/04_create_repository.sh

# 5. Build the ISO (runs mkarchiso with pacstrap)
sudo bash build/05_build_iso.sh
```

The ISO is written to `output/`.

---

## Bundle the Installer

The [AestheticOS Installer](https://github.com/KornienkoDev/AestheticOS-Installer) is baked into the ISO so it launches automatically on boot. To include it:

1. Build the installer (see its [README](https://github.com/KornienkoDev/AestheticOS-Installer)):

   ```bash
   cd AestheticOS-Installer
   ./build.sh
   ```

2. Copy both binaries into the ISO's airootfs:

   ```bash
   cp AestheticOS-Installer/build/bin/aestheticos-installer \
      AestheticOS-Installer/build/bin/aestheticos-installer-cli \
      airootfs/usr/local/bin/
   ```

3. Rebuild the ISO (step 5 of the build pipeline). The binaries are now packaged into `output/`.

On boot, greetd starts Hyprland, which launches `/usr/local/bin/aestheticos-installer`. The `aestheticos` user is granted passwordless sudo via `airootfs/etc/sudoers.d/` so the GUI can run privileged steps through the CLI.

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

### Fully Offline (No Internet Required)

All packages are cached in `airootfs/var/cache/aestheticos/offline-mirror/` and served via `file://` URL in the ISO's pacman.conf. **The installed system has zero network dependency** — every package needed for installation is embedded in the ISO itself.

Because every package is included, **installation takes about 1 minute**, and the **complete OS requires roughly 4.7 GB of disk space** after install.

---

## Requirements

- `archiso` package (for `mkarchiso`)
- `edk2-ovmf` (for QEMU testing)
- `qemu` with KVM support
- An AUR helper (`yay` or similar)
- Root/sudo for package download and ISO build
- ~15 GB of free disk space for the build and the ~4.7 GB installed OS

---

## License

See individual package licenses. This ISO project itself is released under the same license as the Arch Linux packages it bundles.
