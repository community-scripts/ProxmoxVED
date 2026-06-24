#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Karolis Stanelis
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Maintainerr/Maintainerr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  libcairo2 \
  libpango-1.0-0 \
  libjpeg62-turbo \
  libgif7 \
  libpixman-1-0 \
  librsvg2-2
$STD apt install -y \
  build-essential \
  python3 \
  pkg-config \
  libcairo2-dev \
  libpango1.0-dev \
  libjpeg-dev \
  libgif-dev \
  libpixman-1-dev \
  librsvg2-dev
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

fetch_and_deploy_gh_release "maintainerr" "Maintainerr/Maintainerr" "tarball" "latest" "/opt/maintainerr"

msg_info "Building Maintainerr (Patience)"
cd /opt/maintainerr
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export NODE_OPTIONS="--max-old-space-size=768"
$STD corepack enable
$STD corepack prepare yarn@4.11.0 --activate
$STD yarn config set enableTelemetry 0
$STD yarn install --network-timeout 99999999
$STD yarn turbo build --concurrency=1
# Replicate the upstream Dockerfile artifact layout: the server serves the UI
# from dist/ui and loads fonts from dist/assets.
cp -r apps/ui/dist apps/server/dist/ui
cp -r apps/server/assets apps/server/dist/assets
# Replicate docker/start.sh: rewrite the base-path placeholder in the built UI
# (empty BASE_PATH = served from root).
find apps/server/dist/ui -type f -not -path '*/node_modules/*' -print0 | xargs -0 sed -i "s,/__PATH_PREFIX__,,g"
msg_ok "Built Maintainerr"

msg_info "Reclaiming Disk Space"
$STD yarn workspaces focus --all --production
rm -rf /opt/maintainerr/.yarn/cache /opt/maintainerr/.turbo /opt/maintainerr/apps/ui
# NOTE: do NOT purge python3 here. The NodeSource nodejs package depends on it,
# so removing python3 cascades into removing node (and system pkgs like ifupdown2).
$STD apt purge -y \
  build-essential \
  pkg-config \
  libcairo2-dev \
  libpango1.0-dev \
  libjpeg-dev \
  libgif-dev \
  libpixman-1-dev \
  librsvg2-dev
$STD apt autoremove -y
msg_ok "Reclaimed Disk Space"

msg_info "Configuring Environment"
mkdir -p /opt/data/logs
# The app's production TypeORM config hardcodes the migrations path to
# /opt/app/apps/server/dist/database/migrations (the upstream Docker WORKDIR).
# Symlink it so migrationsRun=true finds the migrations and creates the schema.
ln -sfn /opt/maintainerr /opt/app
cat <<EOF >/opt/maintainerr/.env
NODE_ENV=production
DATA_DIR=/opt/data
UI_PORT=6246
UI_HOSTNAME=0.0.0.0
BASE_PATH=
EOF
msg_ok "Configured Environment"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/maintainerr.service
[Unit]
Description=Maintainerr
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/maintainerr/apps/server
EnvironmentFile=/opt/maintainerr/.env
ExecStart=/usr/bin/node dist/main
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now maintainerr
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
