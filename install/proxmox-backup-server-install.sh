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

read -rp "${TAB3}Do you want to use the Enterprise repository (requires valid subscription key)? [y/N]: " USE_ENTERPRISE_REPO

msg_info "Installing Proxmox Backup Server"
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg |
    gpg --dearmor -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
if [[ "$USE_ENTERPRISE_REPO" =~ ^([yY].*)$ ]]; then
    echo "deb https://enterprise.proxmox.com/debian/pbs bookworm pbs-enterprise" >/etc/apt/sources.list.d/pbs-enterprise.list
    msg_ok "Enterprise repository enabled. Make sure your subscription key is installed."
else
    echo "deb http://download.proxmox.com/debian/pbs bookworm pbs-no-subscription" >>/etc/apt/sources.list
    msg_ok "No-subscription repository enabled."
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
