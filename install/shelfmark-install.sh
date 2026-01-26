#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/calibrain/shelfmark

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  unrar-free
ln -sf /usr/bin/unrar-free /usr/bin/unrar
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
PYTHON_VERSION="3.12" setup_uv

fetch_and_deploy_gh_release "shelfmark" "calibrain/shelfmark" "tarball" "latest" "/opt/shelfmark"
RELEASE_VERSION=$(cat "$HOME/.shelfmark")

msg_info "Building Shelfmark frontend"
cd /opt/shelfmark/src/frontend
$STD npm ci
$STD npm run build
mv /opt/shelfmark/src/frontend/dist /opt/shelfmark/frontend-dist
msg_ok "Built Shelfmark frontend"

msg_info "Configuring Shelfmark"
cd /opt/shelfmark
$STD uv venv ./venv
$STD source ./venv/bin/activate
$STD uv pip install -r requirements-base.txt
mkdir -p {/var/log/shelfmark,/tmp/shelfmark,/etc/shelfmark}
cat <<EOF >/etc/shelfmark/.env
DOCKERMODE=false
CONFIG_DIR=/etc/shelfmark
TMP_DIR=/tmp/shelfmark
ENABLE_LOGGING=true
FLASK_HOST=0.0.0.0
FLASK_PORT=8084
RELEASE_VERSION=$RELEASE_VERSION
# SESSION_COOKIES_SECURE=true
# CWA_DB_PATH=
# USE_CF_BYPASS=true
# USING_EXTERNAL_BYPASSER=true
# EXT_BYPASSER_URL=
# EXT_BYPASSER_PATH=
EOF
msg_ok "Configured Shelfmark"

msg_info "Creating Service and start script"
cat <<EOF >/etc/systemd/system/shelfmark.service
[Unit]
Description=Shelfmark server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/shelfmark
EnvironmentFile=/etc/shelfmark/.env
ExecStart=/usr/bin/bash /opt/shelfmark/start.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/opt/shelfmark/start.sh
#!/usr/bin/env bash

source /opt/shelfmark/venv/bin/activate
set -a
source /etc/shelfmark/.env
set +a

gunicorn --worker-class geventwebsocket.gunicorn.workers.GeventWebSocketWorker --workers 1 -t 300 -b 0.0.0.0:8084 shelfmark.main:app
EOF
chmod +x /opt/shelfmark/start.sh

systemctl enable -q --now shelfmark
msg_ok "Created Services and start script"

motd_ssh
customize
cleanup_lxc
