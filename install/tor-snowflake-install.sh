#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: KernelSailor
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://snowflake.torproject.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_go

msg_info "Creating snowflake user"
useradd -r -s /bin/false -d /opt/snowflake snowflake
msg_ok "Created snowflake user"

msg_info "Building Snowflake Proxy from Source"
RELEASE=$(curl -fsSL https://gitlab.torproject.org/api/v4/projects/tpo%2Fanti-censorship%2Fpluggable-transports%2Fsnowflake/releases | jq -r '.[0].tag_name' | sed 's/^v//')
cd /opt
$STD curl -fsSL "https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake/-/archive/v${RELEASE}/snowflake-v${RELEASE}.tar.gz" -o snowflake.tar.gz
$STD tar -xzf snowflake.tar.gz
mv "snowflake-v${RELEASE}" snowflake
rm snowflake.tar.gz
chown -R snowflake:snowflake /opt/snowflake
cd /opt/snowflake/proxy
$STD sudo -u snowflake go build -o snowflake-proxy .
echo "${RELEASE}" >/opt/tor-snowflake_version.txt
msg_ok "Built Snowflake Proxy v${RELEASE}"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/snowflake-proxy.service
[Unit]
Description=Snowflake Proxy Service
Documentation=https://snowflake.torproject.org/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=snowflake
Group=snowflake
WorkingDirectory=/opt/snowflake
ExecStart=/opt/snowflake/proxy/snowflake-proxy -verbose -unsafe-logging
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now snowflake-proxy
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
