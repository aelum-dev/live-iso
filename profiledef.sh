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
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=(xz -9e)
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/sudoers.d/aelum"]="0:0:440"
  ["/home/aelum"]="1000:1000:755"
  ["/usr/local/bin/aelum-installer"]="0:0:755"
  ["/usr/local/bin/aelum-installer-cli"]="0:0:755"
  ["/usr/local/bin/auto-scale-monitor.sh"]="0:0:755"
)
