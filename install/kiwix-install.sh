#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tewalds
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/kiwix/kiwix-tools

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Downloading Kiwix-Tools"
fetch_and_deploy_archive "https://download.kiwix.org/release/kiwix-tools/kiwix-tools_linux-x86_64.tar.gz" /usr/local/bin/
msg_ok "Installed Kiwix binaries"

msg_info "Creating Kiwix Service"
cat <<'EOF' >/etc/systemd/system/kiwix-serve.service
[Unit]
Description=Kiwix ZIM Server
After=network.target

[Service]
Type=simple
# Use shell expansion to serve all .zim files in /data
ExecStart=/bin/sh -c 'exec /usr/local/bin/kiwix-serve --port 8080 /data/*.zim'
Restart=always
RestartSec=10
Nice=15

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/data

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now kiwix-serve
msg_ok "Created and Started Kiwix Service"

motd_ssh
customize
cleanup_lxc
