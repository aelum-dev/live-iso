#!/usr/bin/env python3
"""
Build an offline pacman repository from official Arch packages + AUR packages.

Usage:
    python3 build_repo.py [--force] [--no-copy] [--aur-only] [--official-only]

Caches downloaded packages in /tmp/aestheticos-packages/ to avoid redundant downloads.
Final repo is created at /tmp/aestheticos-packages/repo/ and copied to airootfs/repo/.
"""

import argparse
import glob
import json
import os
import pwd
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

# ── Paths ────────────────────────────────────────────────────────────────────
PROJECT_DIR = Path(__file__).resolve().parent
PACKAGE_LIST_OFFICIAL = PROJECT_DIR / "packages.x86_64"
PACKAGE_LIST_AUR = PROJECT_DIR / "packages.aur.x86_64"
CACHE_BASE = Path("/tmp/aestheticos-packages")
CACHE_OFFICIAL = CACHE_BASE / "official"
CACHE_AUR = CACHE_BASE / "aur"
REPO_DIR = CACHE_BASE / "repo"
AIROOTFS_REPO = PROJECT_DIR / "airootfs" / "repo"

REPO_DB_NAME = "custom.db.tar.zst"


# ── Helpers ──────────────────────────────────────────────────────────────────
def log(msg: str):
    print(f"[build_repo] {msg}")


def _current_user() -> str:
    """Resolve the current non-root username."""
    if os.geteuid() == 0:
        return os.environ.get("SUDO_USER", pwd.getpwuid(os.getuid()).pw_name)
    return pwd.getpwuid(os.getuid()).pw_name


def _aur_api_request(endpoint: str, params: dict) -> dict:
    """Make a request to the AUR RPC API v5 and return the parsed JSON response."""
    url = f"https://aur.archlinux.org{endpoint}"
    query = urllib.parse.urlencode(params, doseq=True)
    full_url = f"{url}?{query}"
    log(f"  AUR API: {endpoint}?{query}")
    try:
        with urllib.request.urlopen(full_url, timeout=30) as response:
            data = json.loads(response.read().decode())
            if data.get("type") == "error":
                log(f"  AUR API error: {data.get('error', 'unknown')}")
                return {"results": []}
            return data
    except Exception as e:
        log(f"  AUR API request failed: {e}")
        return {"results": []}


def read_package_list(filepath: Path) -> list[str]:
    """Read a package list file, skipping comments and blank lines."""
    packages = []
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                packages.append(line)
    return packages


def run(cmd, check=True, **kwargs) -> subprocess.CompletedProcess:
    """Run a command, logging it and optionally raising on failure."""
    # Skip logging for repo-add (too many packages)
    if cmd[0] != "repo-add":
        log(f"  > {' '.join(str(c) for c in cmd)}")
    return subprocess.run(cmd, check=check, **kwargs)


# ── Official packages ────────────────────────────────────────────────────────
def _pacman_cmd():
    """Return the pacman command, using sudo if not root."""
    if os.geteuid() == 0:
        return ["pacman"]
    return ["sudo", "pacman"]


def download_official(packages: list[str], force: bool = False):
    """Download official packages via pacman -Sw into the cache dir."""
    CACHE_OFFICIAL.mkdir(parents=True, exist_ok=True)
    CACHE_AUR.mkdir(parents=True, exist_ok=True)

    # Create a blank dbpath so pacman doesn't skip already-installed deps
    blank_db = CACHE_BASE / "blankdb"
    blank_db.mkdir(parents=True, exist_ok=True)

    # Sync and download with blank dbpath to get all dependencies
    log(f"Downloading {len(packages)} packages with all dependencies...")
    run(
        _pacman_cmd()
        + [
            "-Syw",
            "--cachedir",
            str(CACHE_OFFICIAL),
            "--dbpath",
            str(blank_db),
            "--noconfirm",
        ]
        + packages
    )


# ── AUR packages ─────────────────────────────────────────────────────────────
def _aur_pkg_already_cached(pkg_name: str) -> bool:
    """Check if a built AUR package already exists in the cache."""
    # AUR packages are built inside pkg_name/ subdirectories
    matches = list(CACHE_AUR.rglob(f"{pkg_name}-*.pkg.tar.zst"))
    return len(matches) > 0


def _get_user_cmd():
    """Get command prefix to run as current user (not root)."""
    if os.geteuid() == 0:
        user = _current_user()
        return ["sudo", "-u", user]
    return []


def download_aur_manual(packages: list[str], force: bool = False):
    """Download/build AUR packages via git clone + makepkg."""
    CACHE_AUR.mkdir(parents=True, exist_ok=True)
    user_cmd = _get_user_cmd()

    # If running as root, chown the cache dir to SUDO_USER so makepkg can write
    if os.geteuid() == 0:
        user = _current_user()
        run(["chown", "-R", f"{user}:{user}", str(CACHE_AUR)])

    for pkg in packages:
        pkg_dir = CACHE_AUR / pkg
        pkg_tar_pattern = str(pkg_dir / f"{pkg}-*.pkg.tar.zst")

        if not force and glob.glob(pkg_tar_pattern):
            log(f"  ✓ AUR {pkg} already cached")
            continue

        log(f"  Cloning AUR repo for {pkg}...")
        if pkg_dir.exists():
            run(["git", "-C", str(pkg_dir), "pull"], check=False)
        else:
            run(
                [
                    "git",
                    "clone",
                    f"https://aur.archlinux.org/{pkg}.git",
                    str(pkg_dir),
                ]
            )

        # Chown after git clone/pull — root created these files when run via sudo
        if os.geteuid() == 0:
            user = _current_user()
            run(["chown", "-R", f"{user}:{user}", str(pkg_dir)])

        # Clean previous build artifacts when force-rebuilding
        if force and pkg_dir.exists():
            for d in ["pkg", "src"]:
                dpath = pkg_dir / d
                if dpath.exists():
                    shutil.rmtree(dpath)

        log(f"  Building {pkg} with makepkg...")
        run(user_cmd + ["makepkg", "-s", "--noconfirm", "--force"], cwd=pkg_dir)


def _get_aur_dependencies(packages: list[str]) -> list[str]:
    """Get AUR package dependencies via the AUR RPC API v5.
    
    Note: The AUR API v5 only returns 1 result when multiple arg= params are passed,
    so we must query each package individually.
    """
    extra_deps = []

    for pkg in packages:
        data = _aur_api_request("/rpc/v5/info", {"arg": pkg})
        
        for pkg_info in data.get("results", []):
            pkg_name = pkg_info.get("Name", "")
            deps = pkg_info.get("Depends", [])
            makedeps = pkg_info.get("MakeDepends", [])
            checkdeps = pkg_info.get("CheckDepends", [])

            # Collect all dependency types (except self-reference)
            for dep_list in (deps, makedeps, checkdeps):
                if not dep_list:
                    continue
                for dep in dep_list:
                    # Deps may have version constraints like "glibc>=2.34"
                    dep_name = dep.split(">=")[0].split("<=")[0].split(">")[0].split("<")[0]
                    # Skip empty strings and self-references
                    if dep_name and dep_name != pkg_name and dep_name not in extra_deps:
                        extra_deps.append(dep_name)

    if extra_deps:
        log(f"  Found {len(extra_deps)} extra dependencies from AUR packages via API")
    return extra_deps


def download_aur(packages: list[str], force: bool = False):
    """Download AUR packages via git clone + makepkg (most reliable)."""
    # Get dependencies from AUR API
    extra_deps = _get_aur_dependencies(packages)

    # Store extra deps for the main function to use
    download_aur.extra_deps = extra_deps

    download_aur_manual(packages, force)


# ── Build local repo ────────────────────────────────────────────────────────
def build_local_repo():
    """Merge all cached packages into a single local repo and create its database."""
    REPO_DIR.mkdir(parents=True, exist_ok=True)

    # Collect all .pkg.tar.zst files from official + aur caches, excluding debug packages
    official_pkgs = [
        f for f in CACHE_OFFICIAL.glob("*.pkg.tar.zst")
        if "-debug" not in f.name
    ]
    aur_pkgs = [
        f for f in CACHE_AUR.rglob("*.pkg.tar.zst")
        if "-debug" not in f.name
    ]
    all_pkgs = official_pkgs + aur_pkgs

    if not all_pkgs:
        log("ERROR: No packages found in cache!")
        sys.exit(1)

    log(f"Found {len(all_pkgs)} packages to include in local repo:")
    log(f"  Official: {len(official_pkgs)}")
    log(f"  AUR:      {len(aur_pkgs)}")

    # Copy all packages into the repo directory
    for pkg in all_pkgs:
        dest = REPO_DIR / pkg.name
        if dest.exists():
            dest.unlink()
        shutil.copy2(pkg, dest)

    # Fix ownership consistency (mix of root/user from pacman/makepkg)
    if os.geteuid() == 0:
        # Running as root — chown everything to SUDO_USER so the cache is usable
        user = _current_user()
        run(["chown", "-R", f"{user}:{user}", str(REPO_DIR)])
    else:
        # Running as normal user — pacman ran via sudo, files are root-owned.
        # Need sudo to chown them. If sudo isn't available, warn but continue.
        user = _current_user()
        try:
            run(["sudo", "chown", "-R", f"{user}:{user}", str(REPO_DIR)])
        except subprocess.CalledProcessError:
            log("  WARNING: Could not chown REPO_DIR (pacman files were root-owned). repo-add may fail.")

    # Remove old database if present
    old_db = REPO_DIR / REPO_DB_NAME
    if old_db.exists():
        old_db.unlink()

    # Also remove old .db file if it exists
    old_db_plain = REPO_DIR / "custom.db"
    if old_db_plain.exists():
        old_db_plain.unlink()

    # Create the repo database with repo-add
    db_path = str(REPO_DIR / "custom.db.tar.zst")
    pkg_files = [str(REPO_DIR / pkg.name) for pkg in all_pkgs]

    log("Creating repository database with repo-add...")
    run(["repo-add", db_path] + pkg_files, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    log(f"Local repo created at {REPO_DIR} ({len(all_pkgs)} packages)")


# ── Deploy to airootfs ──────────────────────────────────────────────────────
def deploy_to_airootfs():
    """Copy the built repo into airootfs/repo/."""
    if not REPO_DIR.exists():
        log("ERROR: Repo directory not found. Run build_local_repo() first.")
        sys.exit(1)

    AIROOTFS_REPO.mkdir(parents=True, exist_ok=True)
    shutil.copytree(str(REPO_DIR), str(AIROOTFS_REPO), dirs_exist_ok=True)

    # Fix ownership in deployed repo too
    if os.geteuid() == 0:
        user = _current_user()
        run(["chown", "-R", f"{user}:{user}", str(AIROOTFS_REPO)])
    else:
        # If running as normal user, airootfs/repo/ must be writable by us already
        user = _current_user()
        try:
            run(["sudo", "chown", "-R", f"{user}:{user}", str(AIROOTFS_REPO)])
        except subprocess.CalledProcessError:
            log("  WARNING: Could not chown AIROOTFS_REPO after deploy.")

    log(f"Deployed {len(list(REPO_DIR.glob('*.pkg.tar.zst')))} packages to {AIROOTFS_REPO}")


# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="Build an offline pacman repo from official + AUR packages."
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-download all packages even if cached",
    )
    parser.add_argument(
        "--no-copy",
        action="store_true",
        help="Build the repo but don't copy to airootfs/repo/",
    )
    parser.add_argument(
        "--aur-only",
        action="store_true",
        help="Only process AUR packages",
    )
    parser.add_argument(
        "--official-only",
        action="store_true",
        help="Only process official packages",
    )
    args = parser.parse_args()

    log("=" * 60)
    log("AestheticOS Offline Repo Builder")
    log("=" * 60)

    # Read package lists
    if not args.aur_only:
        official_pkgs = read_package_list(PACKAGE_LIST_OFFICIAL)
        log(f"Official packages: {len(official_pkgs)}")
    else:
        official_pkgs = []
        log("Skipping official packages (--official-only not set, --aur-only set)")

    if not args.official_only:
        aur_pkgs = read_package_list(PACKAGE_LIST_AUR)
        log(f"AUR packages: {len(aur_pkgs)}")
    else:
        aur_pkgs = []
        log("Skipping AUR packages (--aur-only not set, --official-only set)")

    if not official_pkgs and not aur_pkgs:
        log("ERROR: No packages to process!")
        sys.exit(1)

    # Parse AUR dependencies using the AUR RPC API
    extra_aur_deps = []
    if aur_pkgs:
        log("")
        log("── Fetching AUR dependencies via API ──")
        extra_aur_deps = _get_aur_dependencies(aur_pkgs)

    # Combine official packages with AUR dependencies
    all_official_pkgs = list(official_pkgs)
    if extra_aur_deps:
        for dep in extra_aur_deps:
            if dep not in all_official_pkgs:
                all_official_pkgs.append(dep)

    # Download
    if all_official_pkgs:
        log("")
        log("── Official Packages ──")
        if extra_aur_deps:
            log(f"  Including {len(extra_aur_deps)} AUR dependencies")
        download_official(all_official_pkgs, force=args.force)

    if aur_pkgs:
        log("")
        log("── AUR Packages ──")
        download_aur(aur_pkgs, force=args.force)

    # Build repo
    log("")
    log("── Building Local Repo ──")
    build_local_repo()

    # Deploy
    if not args.no_copy:
        log("")
        log("── Deploying to airootfs/repo ──")
        deploy_to_airootfs()

    log("")
    log("=" * 60)
    log("Done! Repo is at:")
    log(f"  Cache:  {CACHE_BASE}")
    log(f"  Local:  {REPO_DIR}")
    if not args.no_copy:
        log(f"  ISO:    {AIROOTFS_REPO}")
    log("=" * 60)


if __name__ == "__main__":
    main()
