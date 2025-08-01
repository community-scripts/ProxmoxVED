#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.proxmox.com/en/proxmox-backup-server

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Proxmox Backup Server"
read -rp "${TAB3}Do you want to use the Enterprise repository (requires valid subscription key)? [y/N]: " USE_ENTERPRISE_REPO

if [[ "$USE_ENTERPRISE_REPO" =~ ^([yY].*)$ ]]; then
  echo "deb https://enterprise.proxmox.com/debian/pbs bookworm pbs-enterprise" >/etc/apt/sources.list.d/pbs-enterprise.list
  sed -i '/pbs-no-subscription/s/^/#/' /etc/apt/sources.list
  msg_custom "Enterprise repository enabled. Make sure your subscription key is installed."
else
  if ! grep -q "pbs-no-subscription" /etc/apt/sources.list; then
    echo "deb http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription" >>/etc/apt/sources.list
  else
    sed -i '/pbs-no-subscription/s/^#//' /etc/apt/sources.list
  fi
  rm -f /etc/apt/sources.list.d/pbs-enterprise.list
fi

$STD apt-get update
$STD apt-get install -y proxmox-backup-server
msg_ok "Installed Proxmox Backup Server"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
