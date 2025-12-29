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
useradd -m -r -s /usr/sbin/nologin -d /home/snowflake snowflake
msg_ok "Created snowflake user"

msg_info "Building Snowflake"
RELEASE=$(curl -fsSL https://gitlab.torproject.org/api/v4/projects/tpo%2Fanti-censorship%2Fpluggable-transports%2Fsnowflake/releases | jq -r '.[0].tag_name' | sed 's/^v//')
$STD bash -c "cd /opt && curl -fsSL 'https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake/-/archive/v${RELEASE}/snowflake-v${RELEASE}.tar.gz' -o snowflake.tar.gz"
$STD bash -c "cd /opt && tar -xzf snowflake.tar.gz"
$STD rm -rf /opt/snowflake.tar.gz
$STD mv /opt/snowflake-v${RELEASE} /opt/tor-snowflake
$STD chown -R snowflake:snowflake /opt/tor-snowflake
$STD sudo -H -u snowflake bash -c "cd /opt/tor-snowflake/proxy && go build -o snowflake-proxy ."
echo "${RELEASE}" >/opt/tor-snowflake/version
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
WorkingDirectory=/opt/tor-snowflake/proxy
ExecStart=/opt/tor-snowflake/proxy/snowflake-proxy -verbose -unsafe-logging
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
