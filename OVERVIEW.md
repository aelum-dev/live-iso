# Offline ArchISO Project

## Overview

A custom offline Arch Linux ISO builder using `mkarchiso`. The ISO contains a curated local repository with packages for both the live environment and future system installation.

## Directory Structure

```
distro/
├── build.sh                    # Main build script
├── run.sh                      # QEMU runner for testing
├── profiledef.sh               # ISO profile definition
├── pacman.conf                 # Host pacman config (for building, [custom] commented out)
├── packages.x86_64             # Packages for the LIVE ISO
├── repo_packages.x86_64        # Packages for the CUSTOM REPO
├── airootfs/                   # Live ISO root filesystem
│   ├── etc/
│   │   ├── pacman.conf         # Live ISO pacman config (points to file:///repo)
│   │   ├── passwd              # User accounts
│   │   ├── shadow              # Password hashes
│   │   ├── group               # Groups
│   │   ├── sudoers.d/
│   │   │   └── aestheticos     # Sudo privileges for aestheticos user
│   │   └── systemd/system/getty@tty1.service.d/
│   │       └── autologin.conf  # Autologin configuration
│   ├── home/aestheticos/       # User home directory
│   └── repo/                   # Local pacman repository (built in-place)
├── out/                        # Output ISO files
├── efiboot/                    # Boot configuration
└── OVMF_VARS.fd               # UEFI variables for QEMU
```

## Package Separation

### `packages.x86_64` (Live ISO)
Packages installed into the live ISO environment:
- `base`, `linux-lts`, `mkinitcpio`, `arch-install-scripts`, `mkinitcpio-archiso`
- `pv`, `sudo`, `vim`, `nano`

These are used by `mkarchiso` to build the live ISO. They are also placed in the local repo so `mkarchiso` can resolve dependencies.

### `repo_packages.x86_64` (Custom Repo)
Packages available in the local repo for system installation:
- `btop`, `fastfetch`

Both package sets (ISO + repo) end up in `airootfs/repo/` because `mkarchiso` installs ISO packages from the repo during build. The repo will contain ISO packages + repo packages + all dependencies.

## Build Process (`build.sh`)

1. **Clean** previous build artifacts
2. **Cache** existing `airootfs/repo` packages to temp directory (avoids re-downloading)
3. **Download** packages from both lists using host pacman (with cache, only new/updated packages fetched)
4. **Copy** all downloaded packages to `airootfs/repo/`
5. **Create** repo database with `repo-add -q`
6. **Run** `mkarchiso` to build the ISO (uses core/extra mirrors, not local repo)

**Note:** The local repo (`airootfs/repo/`) is built in-place — no separate `repo/` directory or copying step needed. The profile's `pacman.conf` has `[custom]` commented out; pacstrap uses core/extra mirrors during build. The final ISO uses `airootfs/etc/pacman.conf` which points to `file:///repo`.

## Live ISO Configuration

- **User:** `aestheticos` (uid 1000, no password)
- **Autologin:** Enabled on tty1 via systemd getty
- **Sudo:** Full root privileges (`ALL=(ALL) ALL`)
- **Pacman:** Points to local repo at `file:///repo`
- **SigLevel:** `Optional TrustAll` for unsigned local repo packages
- **Initramfs:** mkinitcpio (cannot be changed to dracut due to `base` package dependency)

## Filesystem

- **airootfs image:** squashfs (with xz compression)
- **Repo database:** custom.db.tar.zst with custom.files.tar.zst

## Testing

```bash
./run.sh    # Boots ISO in QEMU with KVM
```

## Key Constraints

1. **mkinitcpio is required** for the live ISO — `base` package depends on it, and swapping to dracut for the installed system would require a custom `base` package
2. **Repo contains all packages** — ISO packages must be in the repo for mkarchiso to install them
3. **Offline operation** — no network repos in the final ISO, everything from the local curated repo at `file:///repo`
4. **Pacman 7+ alpm-user isolation** — requires `--dbpath` and `--cachedir` options for package downloads (bypasses download user restrictions)
5. **No text editors in live ISO** for on-the-fly config changes (vi/nano only in ISO, not in minimal install)

## Build Commands

```bash
./build.sh    # Build the ISO
./run.sh      # Test the ISO in QEMU
```
