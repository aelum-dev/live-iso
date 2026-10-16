#!/usr/bin/env bash
#
# Pre-build the Fontconfig cache inside the live ISO image.
#
# Driven by the build-only pacman hook
# etc/pacman.d/hooks/zz-aelum-fontconfig-cache.hook, which runs it once at the
# end of pacstrap (When = PostTransaction, Target = *).
#
# This replaces airootfs/root/customize_airootfs.sh: that extension point is
# deprecated in archiso (mkarchiso's _make_customize_airootfs only runs it after
# printing "customize_airootfs.sh is deprecated") and a pacman hook is the
# supported replacement. The hook - but not this script - is stripped from the
# shipped ISO by zzzz99-remove-custom-hooks-from-airootfs.hook, so the live
# system never sees it (upstream FS#49347).
#
# Why this exists
# ---------------
# The live ISO shipped an empty /var/cache/fontconfig (only CACHEDIR.TAG). The
# first GUI process on every boot is the installer; its GTK/Pango init makes
# Fontconfig enumerate every font before the window can be mapped, so it has to
# cold-read all 893 fonts / ~670 MB through the xz-compressed squashfs.
# Measured on the live ISO with a cold page cache:
#
#     no cache            -> 14.0 s to the installer window
#     prebuilt cache      ->  5.8 s to the installer window
#
# i.e. ~8 s of the black screen was just re-building a cache that never changes.
#
# Why the stock hook is not enough
# --------------------------------
# Fontconfig is supposed to build this cache during pacstrap
# (usr/share/libalpm/hooks/fontconfig.hook runs `fc-cache -s`), yet the shipped
# ISO had no cache at all. The reason is that a Fontconfig cache records the
# mtime of the directory it describes as its checksum - including the sub-second
# part - and that checksum has to survive the trip into the ISO:
#
#  1. SOURCE_DATE_EPOCH is exported by mkarchiso for reproducible builds and is
#     inherited by every pacman hook and chroot command. With it set,
#     FcDirChecksumNano() reports nanosecond 0, while the validation path
#     (FcCacheTimeValid) compares that value against the directory's *real*
#     nanoseconds. The two never match, so fc-cache writes each cache file and
#     deletes it again in the very same run ("invalid cache file"), leaving the
#     directory empty. This is what defeats the pacstrap hook.
#
#  2. squashfs stores whole-second timestamps only, so on the booted ISO every
#     directory reports nanosecond 0 regardless of what it had at build time.
#
#  3. mksquashfs clamps any inode timestamp newer than SOURCE_DATE_EPOCH down to
#     SOURCE_DATE_EPOCH. Font directories are created during pacstrap, i.e. after
#     the build started, so at runtime they all report exactly SOURCE_DATE_EPOCH
#     rather than their build-time mtime.
#
# The fix is to pin every font directory to the mtime the booted ISO will report
# (SOURCE_DATE_EPOCH, or the current second when it is unset) with zero
# nanoseconds, and only then build the cache. A cache produced this way validates
# here and, crucially, in the live system too.
set -uo pipefail

cache_dir=/var/cache/fontconfig
echo "[aelum] pre-building the Fontconfig cache (SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-unset})"

# --- 1. make the font directory mtimes match the booted ISO -------------------
while IFS= read -r -d '' dir; do
    if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
        touch -d "@${SOURCE_DATE_EPOCH}" "$dir"
    else
        touch -d "@$(stat -c %Y "$dir")" "$dir"
    fi
done < <(find /usr/share/fonts /usr/local/share/fonts -type d -print0 2>/dev/null)

# --- 2. drop any half-written cache -------------------------------------------
# CACHEDIR.TAG is left in place.
rm -f "$cache_dir"/*.cache-*

# --- 3. build the cache -------------------------------------------------------
# -f: rebuild even if a cache looks current; -s: system dirs (/usr/share/fonts)
# only, written to /var/cache/fontconfig for every user of the live session.
# SOURCE_DATE_EPOCH is unset so Fontconfig records the real (zero) nanoseconds.
rc=0
env -u SOURCE_DATE_EPOCH fc-cache -f -s || rc=$?
echo "[aelum] fc-cache exit=${rc}"

shopt -s nullglob
caches=("$cache_dir"/*.cache-*)

if (( ${#caches[@]} == 0 )); then
    {
        echo "[aelum] ERROR: Fontconfig cache was not generated under ${cache_dir}"
        echo "[aelum] --- diagnostics ---"
        echo "[aelum] fc-cache exit=${rc}"
        echo "[aelum] fonts: $(find /usr/share/fonts -type f 2>/dev/null | wc -l) file(s), $(du -sh /usr/share/fonts 2>/dev/null | cut -f1)"
        echo "[aelum] fc-list sees $(fc-list 2>/dev/null | wc -l) entries"
        echo "[aelum] font directory mtimes:"
        find /usr/share/fonts -type d -printf '[aelum]   %TY-%Tm-%Td %TH:%TM:%TS %p\n' 2>/dev/null
        echo "[aelum] fc-cache -v -f -s (SOURCE_DATE_EPOCH unset):"
        env -u SOURCE_DATE_EPOCH fc-cache -v -f -s 2>&1
    } >&2
    exit 1
fi

echo "[aelum] Fontconfig cache written: ${#caches[@]} file(s)"

# --- 4. prove the cache validates --------------------------------------------
# A second pass without -f must now find every directory's cache valid. If it
# does not, the cache would be rebuilt on the live system (the black screen we
# are trying to remove), so treat it as a hard failure.
if env -u SOURCE_DATE_EPOCH fc-cache -v -s 2>&1 | grep -q 'caching, new cache contents'; then
    echo "[aelum] ERROR: Fontconfig cache did not validate after being written" >&2
    env -u SOURCE_DATE_EPOCH fc-cache -v -s >&2 2>&1
    exit 1
fi

echo "[aelum] Fontconfig cache verified"
