#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="aestheticos"
iso_label="AESTHETICOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="AestheticOS <https://aestheticos.org>"
iso_application="AestheticOS"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="aestheticos"
buildmodes=('iso')
bootmodes=('uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=(xz -9e)
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/sudoers.d/aestheticos"]="0:0:440"
  ["/home/aestheticos"]="1000:1000:755"
  ["/usr/local/bin/aestheticos-helper"]="0:0:755"
  ["/usr/local/bin/aestheticos-installer"]="0:0:755"
  ["/usr/local/bin/aestheticos-installer-cli"]="0:0:755"
)
