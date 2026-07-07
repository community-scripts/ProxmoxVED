#!/usr/bin/env bash

# Copyright (c) 2021-2026 Juan Lago
# Author: Juan Lago (juanparati)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/RIPE-NCC/ripe-atlas-software-probe

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Setting up RIPE Atlas Repository"
ARCH=$(dpkg --print-architecture)
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
REPO_PKG="ripe-atlas-repo_1.5-5_all.deb"
cd /tmp
curl -fsSLO "https://ftp.ripe.net/ripe/atlas/software-probe/debian/dists/${CODENAME}/main/binary-${ARCH}/${REPO_PKG}"
curl -fsSLO "https://github.com/RIPE-NCC/ripe-atlas-software-probe/releases/latest/download/CHECKSUMS"
if ! grep -q "$(sha256sum "$REPO_PKG")" CHECKSUMS; then
  msg_error "Checksum verification failed for ${REPO_PKG}"
  rm -f "$REPO_PKG" CHECKSUMS
  exit 1
fi
$STD dpkg -i "$REPO_PKG"
rm -f "$REPO_PKG" CHECKSUMS
msg_ok "Set up RIPE Atlas Repository"

msg_info "Installing RIPE Atlas Probe"
$STD apt-get update
$STD apt-get -y install ripe-atlas-probe
echo 'RXTXRPT=yes' >/etc/ripe-atlas/config.txt
systemctl enable -q --now ripe-atlas.service
msg_ok "Installed RIPE Atlas Probe"

motd_ssh
customize
cleanup_lxc
