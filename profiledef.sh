#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="aelum"
iso_label="AELUM_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Aelum <https://aelum.org>"
iso_application="Aelum"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd instead of xz: the kernel decodes one xz LZMA2 stream per block on a
# single core (~90 MB/s), while zstd decodes roughly an order of magnitude
# faster per core. The live ISO also mounts this image with threads=percpu so
# independent blocks decode in parallel (see
# usr/local/share/aelum/squashfs/patch-archiso-mount.sh). Most of the image is
# the offline mirror of already-compressed .pkg.tar.zst packages, which
# mksquashfs stores uncompressed either way, so the size cost is well under the
# raw ratio difference. Level 19 is a size/speed compromise for the build.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
bootstrap_tarball_compression=(xz -9e)
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/sudoers.d/aelum"]="0:0:440"
  ["/home/aelum"]="1000:1000:755"
  ["/usr/local/bin/aelum-installer"]="0:0:755"
  ["/usr/local/bin/aelum-installer-cli"]="0:0:755"
  ["/usr/local/bin/auto-scale-monitor.sh"]="0:0:755"
  # mkinitcpio finds hooks with `type -P`, so both halves of the boot-progress
  # hook need the executable bit (mkarchiso copies airootfs without modes).
  ["/usr/lib/initcpio/hooks/aelum-live"]="0:0:755"
  ["/usr/lib/initcpio/install/aelum-live"]="0:0:755"
)
