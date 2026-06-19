#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Pierre du Plessis
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://solidinvoice.co

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Creating Directories"
mkdir -p /etc/solidinvoice /var/lib/solidinvoice
msg_ok "Created Directories"

ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
[[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
[[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
fetch_and_deploy_gh_release "solidinvoice" "SolidInvoice/SolidInvoice" "singlefile" "latest" "/usr/local/bin" "solidinvoice-linux-${ARCH}"

msg_info "Configuring SolidInvoice"
cat <<'EOF' >/etc/solidinvoice/solidinvoice.env
# SolidInvoice environment configuration
SOLIDINVOICE_CONFIG_DIR=/etc/solidinvoice
SOLIDINVOICE_INSTALL_TYPE=proxmox-community-scripts
#SOLIDINVOICE_PORT=8765
#SOLIDINVOICE_SERVER_IP=0.0.0.0
#SOLIDINVOICE_DOMAIN=
#SOLIDINVOICE_LETS_ENCRYPT=false
EOF
chmod 640 /etc/solidinvoice/solidinvoice.env
msg_ok "Configured SolidInvoice"

msg_info "Creating Service"
cat <<'EOF' >/etc/systemd/system/solidinvoice.service
[Unit]
Description=SolidInvoice
Documentation=https://solidinvoice.co/docs
After=network.target

[Service]
Type=exec
User=root
WorkingDirectory=/var/lib/solidinvoice
ExecStart=/usr/local/bin/solidinvoice run --disable-https --skip-intro --log-format json
EnvironmentFile=/etc/solidinvoice/solidinvoice.env
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now solidinvoice
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
