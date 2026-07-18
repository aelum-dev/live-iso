# Plan: Offline ArchISO with Local Repo

## Concept

Create a **curated local pacman repository** containing all needed packages. This repo serves two purposes:

1. **Build-time**: `mkarchiso` pulls packages from it instead of network mirrors
2. **Live system**: `pacstrap` installs to disk from this same repo (no internet needed)

The repo lives **inside the live system's root filesystem** (compressed in the erofs image), accessible at `/repo/`.

## Directory Structure (after)

```
distro/
├── airootfs/
│   ├── etc/
│   │   └── pacman.conf              # Live system: points to file:///repo
│   └── repo/                        # Local repo --> ends up at /repo/ in live system
│       ├── custom.db.tar.zst
│       ├── custom.files.tar.zst
│       └── *.pkg.tar.zst
├── repo/                            # External local repo (NOT in git, built by script)
│   ├── custom.db.tar.zst
│   ├── custom.files.tar.zst
│   └── *.pkg.tar.zst
├── packages.x86_64                  # Curated package list (live system)
├── pacman.conf                      # Build-time: references external repo
├── profiledef.sh
├── build.sh                         # Updated: builds repo, copies into airootfs
└── .gitignore                       # Add: /repo/
```

## Steps

### Step 1: Create external local repo (build script responsibility)

A new script (or build.sh addition) creates the repo **once** on the host:

```bash
# Create blank db to get proper dependency resolution
mkdir -p /tmp/blankdb
rm -rf /tmp/blankdb/*

# Download ALL packages + deps into repo/
pacman -Syw --cachedir ./repo --dbpath /tmp/blankdb \
  base linux-lts mkinitcpio arch-install-scripts [curated list...]

# Create the repo database
repo-add ./repo/custom.db.tar.zst ./repo/*.pkg.tar.zst
```

The `repo/` directory goes into `.gitignore`.

### Step 2: Modify `pacman.conf` (build-time)

Add the local repo **before** official repos. This conf is only used during ISO build:

```ini
[custom]
SigLevel = Optional TrustAll
Server = file:///home/thinker/Projects/distro/repo

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
```

### Step 3: Create `airootfs/etc/pacman.conf` (live system)

This is placed in the live system. Network repos are **disabled**:

```ini
[options]
SigLevel = PackageRequired
LocalFileSigLevel = Optional

[custom]
SigLevel = PackageRequired
Server = file:///repo

#[core]   -- disabled, offline
#[extra]  -- disabled, offline
```

`PackageRequired` siglevel is used because the packages are signed by the standard Arch keys (already in the live system's keyring from being installed during build).

### Step 4: Copy repo into `airootfs/repo/`

The build script copies the external repo into `airootfs/repo/` so it ends up inside the erofs image at `/repo/` in the live system.

### Step 5: Update `packages.x86_64`

Add `arch-install-scripts` (provides `pacstrap`) and any other curated packages.

## What does NOT change

- `profiledef.sh` -- no changes needed
- `mkarchiso` -- not patched
- Boot configuration -- unchanged
- The erofs/squashfs compression -- unchanged

## Tradeoffs

- The repo files (`.db.tar.zst` + `.pkg.tar.zst`) are **inside the erofs image**, so they're compressed. This saves ISO space but means pacman reads compressed package files (pacman handles this fine).
- The repo is **curated** -- only packages you list will be available. No surprise updates from network repos.
- ISO size will be larger (all packages packed in), but expected for an offline ISO.
