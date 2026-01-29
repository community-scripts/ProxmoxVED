#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://anytype.io

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y ca-certificates
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "anytype" "grishy/any-sync-bundle" "prebuild" "latest" "/opt/anytype" "any-sync-bundle_*_linux_amd64.tar.gz"
chmod +x /opt/anytype/any-sync-bundle

msg_info "Configuring Anytype"
mkdir -p /opt/anytype/data

cat <<EOF >/opt/anytype/.env
ANY_SYNC_BUNDLE_CONFIG=/opt/anytype/data/bundle-config.yml
ANY_SYNC_BUNDLE_CLIENT_CONFIG=/opt/anytype/data/client-config.yml
ANY_SYNC_BUNDLE_INIT_STORAGE=/opt/anytype/data/storage/
ANY_SYNC_BUNDLE_INIT_EXTERNAL_ADDRS=${LOCAL_IP}
ANY_SYNC_BUNDLE_LOG_LEVEL=info
EOF
msg_ok "Configured Anytype"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/anytype.service
[Unit]
Description=Anytype Sync Server (any-sync-bundle)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/anytype
EnvironmentFile=/opt/anytype/.env
ExecStart=/opt/anytype/any-sync-bundle start-all-in-one
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now anytype
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
