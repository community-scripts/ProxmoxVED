#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/RARgames/4gaBoards

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

PG_VERSION="18" setup_postgresql
# Unquoted SQL identifiers cannot start with a digit, so the database is not named after the slug
PG_DB_NAME="boards" PG_DB_USER="boards" setup_postgresql_db

fetch_and_deploy_gh_release "4gaboards" "RARgames/4gaBoards" "tarball"
# Upstream sets engine-strict, so pnpm has to satisfy engines.pnpm (11.x, not the current latest)
NODE_VERSION="24" NODE_MODULE="pnpm@$(jq -r '.engines.pnpm' /opt/4gaboards/package.json)" setup_nodejs

msg_info "Building 4ga Boards"
cd /opt/4gaboards
$STD pnpm install --frozen-lockfile --filter "client..." --filter "server..."
$STD pnpm packages:build
DISABLE_ESLINT_PLUGIN=true $STD pnpm client:build
cp -r client/build/. server/public/
cp client/build/index.html server/views/index.ejs
msg_ok "Built 4ga Boards"

msg_info "Configuring 4ga Boards"
mkdir -p /opt/4gaboards_data/{attachments,user-avatars,project-background-images}
cat <<EOF >/opt/4gaboards_data/.env
NODE_ENV=production
BASE_URL=http://${LOCAL_IP}:1337
SECRET_KEY=$(openssl rand -hex 64)
DATABASE_URL=postgresql://boards:${PG_DB_PASS}@localhost/boards
DEFAULT_ADMIN_USERNAME=admin
DEFAULT_ADMIN_EMAIL=admin@4gaboards.local
DEFAULT_ADMIN_NAME=Administrator
DEFAULT_ADMIN_PASSWORD=$(random_password)
EOF
chmod 600 /opt/4gaboards_data/.env
# Upload paths are fixed relative to the app, so they are linked out of the directory an update wipes
rm -rf /opt/4gaboards/server/private/attachments /opt/4gaboards/server/public/user-avatars /opt/4gaboards/server/public/project-background-images
ln -s /opt/4gaboards_data/attachments /opt/4gaboards/server/private/attachments
ln -s /opt/4gaboards_data/user-avatars /opt/4gaboards/server/public/user-avatars
ln -s /opt/4gaboards_data/project-background-images /opt/4gaboards/server/public/project-background-images
ln -s /opt/4gaboards_data/.env /opt/4gaboards/server/.env
cd /opt/4gaboards/server
$STD node db/init.js
msg_ok "Configured 4ga Boards"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/4gaboards.service
[Unit]
Description=4ga Boards
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/4gaboards/server
ExecStart=/usr/bin/node app.js --prod
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now 4gaboards
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
