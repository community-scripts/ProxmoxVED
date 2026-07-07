#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
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
REPO_URL="https://ftp.ripe.net/ripe/atlas/software-probe/debian/dists/${CODENAME}/main/binary-${ARCH}"
REPO_PKG=$(curl -fsSL "${REPO_URL}/" | grep -oE 'ripe-atlas-repo_[^"]+_all\.deb' | sort -uV | tail -1)
cd /tmp
curl -fsSLO "${REPO_URL}/${REPO_PKG}"
curl -fsSLO "https://github.com/RIPE-NCC/ripe-atlas-software-probe/releases/latest/download/CHECKSUMS"
if ! grep -qF "$(sha256sum "$REPO_PKG")" CHECKSUMS; then
  msg_error "Checksum verification failed for ${REPO_PKG}"
  rm -f "$REPO_PKG" CHECKSUMS
  exit 1
fi
$STD dpkg -i "$REPO_PKG"
rm -f "$REPO_PKG" CHECKSUMS
msg_ok "Set up RIPE Atlas Repository"

msg_info "Installing RIPE Atlas Probe"
$STD apt update
$STD apt install -y ripe-atlas-probe
cat <<EOF >/etc/ripe-atlas/config.txt
RXTXRPT=yes
EOF
systemctl enable -q --now ripe-atlas.service
msg_ok "Installed RIPE Atlas Probe"

msg_info "Waiting for probe key generation"
for i in {1..15}; do
  [[ -s /etc/ripe-atlas/probe_key.pub ]] && break
  sleep 2
done
if [[ ! -s /etc/ripe-atlas/probe_key.pub ]]; then
  # Fallback: generate the key pair manually (same parameters RIPE documents)
  ssh-keygen -t rsa -b 2048 -P '' -C software-probe -f /etc/ripe-atlas/probe_key >/dev/null 2>&1
  chown ripe-atlas:ripe-atlas /etc/ripe-atlas/probe_key /etc/ripe-atlas/probe_key.pub 2>/dev/null || true
  systemctl restart ripe-atlas.service
fi
msg_ok "Probe key ready"

motd_ssh
customize
cleanup_lxc
