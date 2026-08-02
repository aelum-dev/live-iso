# AestheticOS

A custom Arch Linux live ISO with a focus on aesthetics: seamless silent boot with Plymouth BGRT theme, greetd login manager, and a fully offline package mirror.

---

## Features

- **Silent boot** — no kernel messages, no console spam, just your OEM logo (BGRT) and a clean splash
- **Plymouth BGRT theme** — preserves your UEFI firmware logo as the boot splash, flicker-free via SimpleDRM
- **greetd + agreety** — fast, minimal login manager
- **Fully offline** — all packages cached in a local repo, zero network dependency after build
- **AUR support** — yay-bin and other AUR packages built into the ISO
- **Systemd-boot (UEFI)** — clean EFI boot loader with deferred console takeover to retain the vendor logo

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
│   │   ├── greetd/            # greetd login manager config
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

### Offline Mirror

All packages are cached in `airootfs/var/cache/aestheticos/offline-mirror/` and served via `file://` URL in the ISO's pacman.conf. The installed system has zero network dependency.

---

## Customization

### Change the Plymouth theme

```bash
sudo plymouth-set-default-theme -R <theme>
```

Available themes: `bgrt`, `fade-in`, `glow`, `script`, `solar`, `spinner`, `spinfinity`, `text`, `tribar`, `details`

### Add a fallback BGRT image

If your UEFI doesn't provide a BGRT logo:

```
/usr/share/plymouth/themes/spinner/bgrt-fallback.png
```

Or set `UseFirmwareBackground=true` in `plymouthd.conf` to keep the firmware background.

### Adjust animation delay

For fast boots where the splash flickers, edit `airootfs/etc/plymouth/plymouthd.conf`:

```ini
[Daemon]
ShowDelay=5
```

Or enable the animation wait service:

```bash
sudo systemctl enable plymouth-wait-for-animation.service
```

---

## Requirements

- `archiso` package (for `mkarchiso`)
- `edk2-ovmf` (for QEMU testing)
- `qemu` with KVM support
- An AUR helper (`yay` or similar)
- Root/sudo for package download and ISO build

---

## License

See individual package licenses. This ISO project itself is released under the same license as the Arch Linux packages it bundles.
