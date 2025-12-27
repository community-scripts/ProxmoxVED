#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://linkwarden.app/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y build-essential
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs
PG_VERSION="16" setup_postgresql
PG_DB_NAME="linkwardendb" PG_DB_USER="linkwarden" setup_postgresql_db
RUST_CRATES="monolith" setup_rust
fetch_and_deploy_gh_release "linkwarden" "linkwarden/linkwarden"
import_local_ip

read -r -p "${TAB3}Would you like to add Adminer? <y/N> " prompt
if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
  setup_adminer
fi

msg_info "Installing Linkwarden (Patience)"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export PRISMA_HIDE_UPDATE_MESSAGE=1
export DEBIAN_FRONTEND=noninteractive
corepack enable
SECRET_KEY="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)"
cd /opt/linkwarden
$STD yarn workspaces focus linkwarden @linkwarden/web @linkwarden/worker
# $STD npx playwright install-deps
# $STD yarn playwright install

cat <<EOF >/opt/linkwarden/.env
NEXTAUTH_SECRET=${SECRET_KEY}
NEXTAUTH_URL=http://${LOCAL_IP}:3000
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
EOF
$STD yarn prisma:generate
$STD yarn web:build
$STD yarn prisma:deploy
rm -rf ~/.cargo/registry ~/.cargo/git ~/.cargo/.package-cache
rm -rf /root/.cache/yarn
rm -rf /opt/linkwarden/.next/cache
msg_ok "Installed Linkwarden"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/linkwarden.service
[Unit]
Description=Linkwarden Service
After=network.target

[Service]
Type=exec
Environment=PATH=$PATH
WorkingDirectory=/opt/linkwarden
ExecStart=/usr/bin/yarn concurrently:start

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now linkwarden
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
