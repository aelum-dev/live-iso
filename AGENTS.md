# Aelum live-iso — Agent Context

This repo is the **archiso profile**: the content that goes into the Aelum live ISO. Nothing here
builds an ISO — `docker/` clones this repo, builds the installer, fills the offline mirror and runs
`mkarchiso` (see `docker/AGENTS.md` for which build command to use). `README.md` is for users;
this file is the part an agent must not relearn the expensive way.

Cross-repo rules live in the workspace-root `AGENTS.md` — especially *live ISO vs installed
system* (`/mnt/*` + `arch-chroot` = the target, `/dev/*` + direct exec = the live session) and
*artifacts are never source*.

## Layout

```
profiledef.sh              # ISO name/label/version, bootmodes, squashfs options, file_permissions
packages.x86_64            # packages in the live session (official + the distro's own apps,
                           # aelum-video-player and aelum-package-installer, which the
                           # build resolves from the [aelum] repo and bakes into the mirror)
packages.aur.x86_64        # AUR packages built into the offline mirror (not installed in the live
                           # session — mkarchiso reads only packages.x86_64)
bootstrap_packages         # bootstrap environment
pacman-offline.conf        # pacman config mkarchiso itself uses (blank DB + offline mirror)
airootfs/
  etc/greetd/              # greetd + Hyprland autostart → the installer
  etc/mkinitcpio.conf.d/   # live-ISO hooks (kms, aelum-live, …)
  etc/mkinitcpio.d/        # kernel preset
  etc/pacman.conf          # the LIVE SESSION's config (file:// offline mirror) — never copied to the target
  etc/pacman.d/hooks/      # squashfs mount threads, fontconfig cache, hook cleanup
  etc/polkit-1/            # snapshot-restore action + rule
  etc/plymouth/            # splash daemon config
  etc/quickshell/aelum-snapshot/   # snapshot-boot restore dialog + generated i18n/
  etc/skel/                # what every new home is seeded from (dms, hypr, kitty, systemd user units)
  etc/systemd/             # system units (live boot progress) + user units (snapshot prompt)
  home/aelum/              # live user's home, incl. the dms.service mask
  usr/local/bin/           # aelum-installer{,-cli} (built, gitignored), aelum-snapshot-restore, theming scripts
  usr/local/share/aelum/   # squashfs mount patch, fontconfig setup
  usr/lib/initcpio/        # aelum-live boot-progress hook (both halves)
  usr/share/aelum/         # brand assets: wallpapers, rEFInd theme (generated PNGs),
                           # keyring/aelum-release.gpg (the [aelum] repo's signing key)
  usr/share/plymouth/themes/aelum/  # branded splash theme
grub/  syslinux/           # boot configs (uefi.grub, bios.syslinux)
efiboot/                   # leftover from the old systemd-boot profile — unused
images/                    # README hero
```

Ignored after a local build: `work/`, `output/`, `airootfs/var/cache/aelum/offline-mirror/`,
`airootfs/usr/local/bin/aelum-installer{,-cli}`.

## Generated files — regenerate, never hand-edit

| Output | Generator |
|---|---|
| `usr/share/aelum/refind/themes/aelum/*.png` | `python3 scripts/gen-refind-theme.py` (`--icons-only` while iterating; `AELUM_NERD_FONT=` if the repos aren't side by side) |
| `etc/xdg/quickshell/aelum-snapshot/i18n/<locale>.json` | `installer/backend/scripts/gen-snapshot-prompt-i18n.go`, from the installer's `snapshot.prompt.*` translations |
| `airootfs/usr/local/bin/aelum-installer{,-cli}` | the installer build (`docker/build-iso.sh` copies them in) |
| `etc/skel/.config/gtk-{3.0,4.0}/dank-colors.css` + `etc/skel/.cache/dms/dms-colors.json` | Dux Shell + matugen on a desktop using the shipped wallpaper, in the mode `etc/skel/.cache/dms/dms-colors.json` is seeded in, under the `"matugenSpec"` seeded in `etc/skel/.config/dms/settings.json` — the palette comes out byte-identical for gtk-3.0 and gtk-4.0 (see "The seeded theme state is one mode") |
| `usr/share/aelum/keyring/aelum-release.gpg` | `gpg --export 728F5F59FB2F5A88C6EE28D4930A672A3A1B5B60` (the Aelum release key). The installer copies it to the target (isocopy job) and feeds it to `pacman-key --add` + `--lsign-key` so the `[aelum]` repository verifies from the first boot — regenerate only on key rotation |
| `images/hero-dark.png` | copy of `website/assets/desktop-control-dark.png` (2560×1440) when the site's desktop shots change |

Commit the regenerated artifact in the same commit as the change that needs it. The rEFInd icon set
shares one source font with the website and the installer (`website/scripts/SymbolsNerdFont-Regular.ttf`,
via `website/scripts/icons.py`), so a glyph added once is available to all three.

## Rules that cost real debugging time

- **`mkarchiso` copies `airootfs` without exec bits.** Anything executable must be declared in
  `profiledef.sh`'s `file_permissions` with `0755`: both installer binaries, `auto-scale-monitor.sh`,
  `aelum-theme-watch.sh`, both halves of the `aelum-live` initcpio hook (mkinitcpio finds hooks with
  `type -P`), and `aelum-snapshot-restore` (pkexec refuses to authenticate a program it cannot exec —
  silently, with nothing in the log).
- **Neither pacman.conf is the installed system's.** `pacman-offline.conf` is what the *build* uses
  (empty DB path, so `pacman -Syw` pulls only dependency trees); `airootfs/etc/pacman.conf` is what the
  **live session** uses (`[aelum-offline] Server = file:///var/cache/aelum/offline-mirror`) — that is
  why `pacstrap` resolves every name from the mirror (install logs: `aelum-offline downloading...`).
  The repo DB is generated during the build. Nothing carries that config into the target:
  `installbase` runs `pacstrap -K /mnt …`, and pacstrap copies the host's config only with `-P`; no
  installer step writes `pacman.conf` or anything in `etc/pacman.d/` except the mirrorlist
  (`installer/backend/install/configure/system.go`). So an installed system runs the **stock
  `pacman.conf` from the `pacman` package** (core/extra/multilib + `Include =
  /etc/pacman.d/mirrorlist`). The offline mirror is install-time only — installed systems update from
  normal mirrors. Anything that must add a repo to an installed system has to be **written by the
  installer**, not shipped from `airootfs`.
- **`[aelum]` is not in `pacman-offline.conf`, on purpose.** The distro's own repository is resolved
  by the *build* (`docker/scripts/build-iso.sh`: a generated `Include = /etc/pacman.conf` + `[aelum]`
  config, `SigLevel = Never` scoped to that repo) and the resolved packages are baked into the offline
  mirror before `mkarchiso` runs. So the distro's own apps (`aelum-video-player`,
  `aelum-package-installer`) reach the live session through
  `[aelum-offline]` like every other package, and mkarchiso stays strictly on the mirror: a live
  session holding a newer version than the mirror carries is the silent bug this avoids. If the repo
  is unreachable, the build fails loudly instead of quietly shipping without the package.
- **Squashfs is zstd `-Xcompression-level 19 -b 1M`, on purpose.** The kernel decodes one xz stream
  per block on a single core; zstd is roughly an order of magnitude faster per core, and the live ISO
  mounts the image with `threads=percpu` (`etc/pacman.d/hooks/50-aelum-squashfs-threads.hook`,
  `usr/local/share/aelum/squashfs/patch-archiso-mount.sh`). Most of the image is already-compressed
  `.pkg.tar.zst`, so the size cost is small. Don't "improve" this back to xz.
- **`etc/resolv.conf` must stay the symlink** to `/run/systemd/resolve/stub-resolv.conf` (networkd +
  resolved are enabled in `etc/systemd/system/multi-user.target.wants/`). Tools that read
  `/etc/resolv.conf` directly — GnuPG's `dirmngr` above all — get no nameserver from the
  comment-only file `filesystem` ships when the symlink is missing: `curl`/`getent` still work through
  `nss-resolve`, WKD lookups fail.
- **The live initramfs has no `autodetect`.** The image must boot anywhere, so the `kms` hook carries
  every DRM driver (`amdgpu`, `radeon`, `i915`, `xe`, `nouveau`, `virtio_gpu`, `vmwgfx`, …) and `udev`
  loads the matching one. That is what gives the panel early KMS — no `simpledrm` hand-off, no
  mode-set flicker before the splash. The *installed* system gets `autodetect` + `kms` from the
  installer instead.
- **`aelum-live` must stay after `plymouth` in `HOOKS`** (`etc/mkinitcpio.conf.d/archiso.conf`): it
  only talks to a running `plymouthd`, and its `run_latehook` has to run after plymouth's.
- **The live session is installer-only by a mask, not by omission.** archiso seeds every home from
  `/etc/skel` at build time ("Copying /etc/skel/* to user homes"), and Hyprland ≥ 0.57 starts
  `hyprland-session.target` itself (hyprwm/Hyprland#15776; skipped under an existing unit via
  `$MANAGERPID`, off with `HYPRLAND_NO_SD_TARGET`). So the wants links seeded for the *installed*
  desktop fire in the live session too — which is why Dux Shell started autostarting in Oct 2026.
  `home/aelum/.config/systemd/user/dms.service` is an **empty file**, i.e. masked: the wants link
  stays, the unit cannot start, and the target still reaches `graphical-session.target` (what
  xdg-desktop-portal needs). The seeded `aelum-snapshot-prompt.service` link is deliberately *not*
  masked — its `ConditionPathExists` gate fails on its own there. Installed homes come from
  `/etc/skel`, which carries no mask.
- **The snapshot-restore path is source here, not installer output.** `usr/local/bin/aelum-snapshot-restore`,
  the polkit policy + `wheel`-member rule, `etc/xdg/quickshell/aelum-snapshot/shell.qml` (+ its i18n),
  and `etc/systemd/user/aelum-snapshot-prompt.service` are copied into a btrfs target **unchanged** by
  the installer's `install/isocopy` jobs, before the "after installation" snapshot is taken (a snapshot
  runs the files it contains). They are inert in the live session by design — no `/run/aelum-snapshot-boot`,
  no `root` snapper config — so do not "fix" the live session by running them. What proves them:
  `docker/scripts/fake-snapshot-restore.sh` (host, stubs, no root) and `docker/scripts/verify-installed.sh`,
  which byte-compares the installed copies against these files after a real install.
- **rEFInd is per-install.** The installer copies `usr/share/aelum/refind/themes/aelum` to
  `EFI/refind/themes/aelum` and includes it from `refind.conf`; each install then writes its own
  `EFI/refind/aelum/<id>.conf` (plus `<id>-snapshots.conf` on btrfs) and keeps its kernel and
  initramfs in `aelum/<id>/`, so nothing one install writes can land on another's. That isolation is
  never tested against a shared ESP, though: **each install owns its own ESP** — manual mode always
  formats the Boot partition it is given (installer `1f30229`), so a second install on the same disk
  takes its own Boot + System partition.
- **rEFInd artwork has fixed size rules.** Icons and selections are generated at 2× because rEFInd
  doubles icons at ≥1921px screen width (256px OS icons are native on 2K/4K, downscaled on 1080p; tool
  glyphs 96px, volume badges 64px, mouse 32px). rEFInd does not scale custom fonts, so the installer
  picks `font-2x.png` whenever the mode is ≥1921px wide. Font glyphs are drawn **black** in the PNG —
  rEFInd inverts them on the dark background to render menu text white. The theme overrides every
  stock icon, tool and badge so no stock artwork is ever shown.
- **Firefox's uBlock Origin is a policy, not a package.** `usr/lib/firefox/distribution/policies.json`
  force-installs it from addons.mozilla.org by add-on ID (`uBlock0@raymondhill.net`) on first launch, so
  nothing is bundled in the ISO and the add-on needs the network the first time Firefox runs. The same
  file locks `widget.gtk.libadwaita-colors.enabled` off so GTK apps keep the matugen palette.
- **The seeded theme state is one mode, in five files.** Nothing in an installed session puts a
  palette into GTK before Dux Shell has applied one, so what `etc/skel` and the copied dconf
  keyfiles leave behind is what the first app of the first session sees. The files that name that
  state: `.cache/dms/dms-colors.json` (`"mode"`), `.config/gtk-3.0/dank-colors.css` and
  `.config/gtk-4.0/dank-colors.css` (the palette GTK reads), `.config/gtk-{3.0,4.0}/settings.ini`
  and `etc/dconf/db/local.d/01-icons` (the icon variant), and `etc/dconf/db/local.d/03-dark-theme`
  (`gtk-theme` + `color-scheme`, which is what GTK4, libadwaita and the settings portal read —
  copied to the target too; Dux Shell writes the same keys per mode into the user database, and the
  user database wins, so switching the mode still overrides it). A light palette under a dark seeded
  mode is what made a first-start Firefox render plain Adwaita until the mode was switched.
  The two palette files are **Dux Shell's own output** — regenerate them from a Dux Shell desktop
  running that mode (they come out byte-identical for gtk-3.0 and gtk-4.0), never write one by
  hand. The generation runs under a **pinned matugen spec**: `settings.json` seeds
  `"matugenSpec": "2025"` and `dms-colors.json` is that spec's output. The current default spec
  derives different colors from the same wallpaper (background `#141218` vs `#0f0d12`), so a
  baseline regenerated without the pin silently restyles every installed desktop — and a
  `dms-colors.json` whose values disagree with the palette files is what made a host on the 2025
  spec and a fresh install disagree on screen. `.config/gtk-3.0/gtk.css` is a symlink to `dank-colors.css` and is the whole GTK3 half of
  the chain: without it a GTK3 app (Firefox is one — `libmozgtk.so` links `libgtk-3.so.0`) loads its
  theme and never sees the palette. `gtk-4.0/gtk.css` imports the palette and nothing else; an import
  of a file nothing writes is dead config plus a parser error on every app start. What proves it:
  `docker/scripts/verify-installed.sh` (mode ↔ palette ↔ icon variant, on a real install) and
  `shared/aelum-color-probe.sh` (what a booted session renders with no theme applied).
- **The player owns media; mpv is hidden by a skel override.** `~/.local/share/applications/mpv.desktop`
  (seeded, `NoDisplay=true`, no `MimeType` line) replaces the package's entry in every launcher's view —
  a home-local file package updates never touch, so hiding survives every mpv upgrade; the dms binary
  honors `NoDisplay` (measured against its strings). `~/.config/mimeapps.list` defaults every type the
  player's own desktop entry declares to `aelum.videoplayer.Player.desktop` — keep the two lists in sync
  when the player's `MimeType` set changes. The player's `float` + `opaque` + `keep_aspect_ratio` window
  rule (class = the GTK4 app id `aelum.videoplayer.Player`) lives in the skel `hyprland.lua`, like the
  snapshot prompt's. The compositor locks the **window's** ratio — the box, header bar and playback bar
  included — so the video area keeps a slightly different one; an app-side lock would have to read the
  chrome heights.
- **`auto-scale-monitor.sh` is live-session only.** It runs from the live user's Hyprland config
  (`home/aelum/.config/hypr/hyprland.lua` and `dms/outputs.lua`), not from `/etc/skel`, so installed
  homes never start it. The installed system has no automatic monitor scaling yet — don't describe it
  as an installed feature.
- `efiboot/` is left over from the old systemd-boot profile. Nothing uses it.

## License

GPL-3.0 (`LICENSE`).
