#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Arubinu
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/fosrl/newt

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

ARCH=$(get_system_arch dpkg)
fetch_and_deploy_gh_release "newt" "fosrl/newt" "singlefile" "latest" "/opt/newt" "newt_linux_${ARCH}"
ln -sf /opt/newt/newt /usr/local/bin/newt

ensure_whiptail
NEWT_ID="${NEWT_ID:-$(whiptail --backtitle "Proxmox VE Helper Scripts" \
  --title "Newt Site ID" \
  --inputbox "Newt ID (from your Pangolin dashboard)" 8 70 3>&1 1>&2 2>&3)}"

NEWT_SECRET="${NEWT_SECRET:-$(whiptail --backtitle "Proxmox VE Helper Scripts" \
  --title "Newt Secret" \
  --passwordbox "Newt Secret" 8 70 3>&1 1>&2 2>&3)}"

PANGOLIN_ENDPOINT="${PANGOLIN_ENDPOINT:-$(whiptail --backtitle "Proxmox VE Helper Scripts" \
  --title "Pangolin Endpoint" \
  --inputbox "Pangolin server URL (e.g. https://pangolin.example.com)" 8 70 3>&1 1>&2 2>&3)}"

if [[ -z "$NEWT_ID" || -z "$NEWT_SECRET" || -z "$PANGOLIN_ENDPOINT" ]]; then
  msg_error "Newt ID, Secret and Endpoint are all required. Aborting."
  exit 1
fi

msg_info "Configuring Newt"
mkdir -p /etc/newt
cat >/etc/newt/newt.env <<ENVEOF
NEWT_ID=${NEWT_ID}
NEWT_SECRET=${NEWT_SECRET}
PANGOLIN_ENDPOINT=${PANGOLIN_ENDPOINT}
ENVEOF
chmod 600 /etc/newt/newt.env
msg_ok "Configured Newt"

msg_info "Creating Service"
cat >/etc/systemd/system/newt.service <<SVCEOF
[Unit]
Description=Newt (Pangolin tunnel client)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/newt/newt.env
ExecStart=/usr/local/bin/newt
Restart=always
RestartSec=2
UMask=0077
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SVCEOF
systemctl enable -q --now newt
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
