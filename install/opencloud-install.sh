#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://opencloud.eu

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# msg_info "Installing Dependencies"
# $STD apt-get install -y \
#   build-essential
# msg_ok "Installed Dependencies"

msg_info "Installing ${APPLICATION}"
RELEASE=$(curl -s https://api.github.com/repos/opencloud-eu/opencloud/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
curl -fsSL "https://github.com/opencloud-eu/opencloud/releases/download/v${RELEASE}/opencloud-${RELEASE}-linux-amd64" -o /usr/bin/opencloud
chmod +x /usr/bin/opencloud
echo "${RELEASE}" >/etc/opencloud/version
msg_ok "Installed ${APPLICATION}"

msg_info "Configuring ${APPLICATION}"
DATA_DIR="/var/lib/opencloud/"
CONFIG_DIR="/etc/opencloud"
ENV_FILE="${CONFIG_DIR}/opencloud.env"
IP="$(hostname -I | awk '{print $1}')"

cat <<EOF >"$ENV_FILE"
OC_URL=https://${IP}:9200
OC_INSECURE=true
PROXY_ENABLE_BASIC_AUTH=true
IDM_CREATE_DEMO_USERS=false
OC_LOG_LEVEL=warning
OC_CONFIG_DIR=${CONFIG_DIR}
OC_BASE_DATA_PATH=${DATA_DIR}
EOF

cat <<EOF >/etc/systemd/system/opencloud.service
[Unit]
Description=OpenCloud server

[Service]
Type=simple
User=opencloud
Group=opencloud
EnvironmentFile=${ENV_FILE}
ExecStart=/usr/bin/opencloud server
Restart=always

[Install]
WantedBy=multi-user.target
EOF

useradd -r -M -s /usr/sbin/nologin opencloud
chown -R opencloud:opencloud "$CONFIG_DIR" "$DATA_DIR"
sudo -u opencloud opencloud init --config-path "$CONFIG_DIR" --insecure yes
systemctl enable -q --now opencloud.service
msg_ok "Configured ${APPLICATION}"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
