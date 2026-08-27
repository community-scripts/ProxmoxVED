#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Pascal de Vink (pascaldevink)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://atuin.sh/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PG_VERSION="17" setup_postgresql
PG_DB_NAME="atuin" PG_DB_USER="atuin" setup_postgresql_db

msg_info "Installing Atuin"
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/atuinsh/atuin/releases/latest/download/atuin-server-installer.sh | ATUIN_SERVER_INSTALL_DIR="/opt/atuin" $STD sh
cat <<EOF >/opt/atuin/server.toml
host = "0.0.0.0"
port = 8888
open_registration = true
db_uri = "postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}"
EOF
msg_ok "Installed Atuin"

msg_info "Creating Service"
cat <<'EOF' >/etc/systemd/system/atuin.service
[Unit]
Description=Atuin
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/atuin/
ExecStart=/opt/atuin/atuin-server start
Restart=always
RestartSec=5

Environment=ATUIN_CONFIG_DIR=/opt/atuin
ReadWritePaths=/opt/atuin

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now atuin

cat <<EOF >~/.atuin
$(get_latest_github_release "atuinsh/atuin")
EOF
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
