#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Harrison (germondai)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/germondai/trawl

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  fonts-liberation \
  libasound2t64 \
  libatk-bridge2.0-0t64 \
  libatk1.0-0t64 \
  libcairo2 \
  libcairo-gobject2 \
  libdbus-1-3 \
  libdbus-glib-1-2 \
  libfontconfig1 \
  libgdk-pixbuf-2.0-0 \
  libglib2.0-0t64 \
  libgtk-3-0t64 \
  libnspr4 \
  libnss3 \
  libpango-1.0-0 \
  libpangocairo-1.0-0 \
  libx11-6 \
  libx11-xcb1 \
  libxcb-shm0 \
  libxcb1 \
  libxcomposite1 \
  libxcursor1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxi6 \
  libxrandr2 \
  libxrender1 \
  libxss1 \
  libxtst6 \
  libdrm2 \
  libgbm1 \
  python3 \
  redis-server \
  unzip
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

# setup_nodejs provides Node.js and npm but removes Debian's packaged Node.js toolchain.
# Install node-gyp from npm because better-sqlite3 invokes it during Bun's install.
msg_info "Installing node-gyp"
$STD npm install --global node-gyp
msg_ok "Installed node-gyp"

msg_info "Installing Bun"
export BUN_INSTALL="/root/.bun"
curl -fsSL https://bun.sh/install | $STD bash
ln -sf /root/.bun/bin/bun /usr/local/bin/bun
ln -sf /root/.bun/bin/bunx /usr/local/bin/bunx
msg_ok "Installed Bun"

systemctl enable -q --now redis-server

fetch_and_deploy_gh_release "trawl" "germondai/trawl" "tarball"

msg_info "Configuring TRAWL"
mkdir -p /opt/trawl_data/proxy-ca /opt/trawl_data/camoufox
cat <<EOF >/etc/trawl.env
PORT=8191
REDIS_URL=redis://127.0.0.1:6379
BROWSER_POOL_SIZE=1
BROWSER_CONTENT_PROCESSES=2
CAMOUFOX_INSTALL_DIR=/opt/trawl_data/camoufox
MITM_PROXY_ENABLED=false
MITM_PROXY_PORT=8192
MITM_PROXY_HOST=127.0.0.1
MITM_PROXY_CA_DIR=/opt/trawl_data/proxy-ca
MITM_PROXY_MAX_TIER=4
EOF
chmod 640 /etc/trawl.env
msg_ok "Configured TRAWL"

msg_info "Installing Bun Dependencies"
cd /opt/trawl
$STD bun install --frozen-lockfile --production --omit=dev --linker=hoisted
msg_ok "Installed Bun Dependencies"

CAMOUFOX_BUILD=$(arch_resolve "alpha.26" "alpha.25")
CAMOUFOX_ARCH=$(arch_resolve "x86_64" "arm64")
fetch_and_deploy_from_url \
  "https://github.com/daijro/camoufox/releases/download/v150.0.2-beta.25/camoufox-150.0.2-${CAMOUFOX_BUILD}-lin.${CAMOUFOX_ARCH}.zip" \
  "/opt/trawl_data/camoufox"
curl_download \
  "/opt/trawl_data/camoufox/GeoLite2-City.mmdb" \
  "https://github.com/P3TERX/GeoLite.mmdb/releases/latest/download/GeoLite2-City.mmdb"
[[ "$(stat -c%s /opt/trawl_data/camoufox/GeoLite2-City.mmdb)" -gt 10000000 ]] || {
  msg_error "GeoLite2-City.mmdb download is incomplete"
  exit 1
}
cat <<EOF >/opt/trawl_data/camoufox/version.json
{"version":"150.0.2","release":"${CAMOUFOX_BUILD}"}
EOF
chmod -R 755 /opt/trawl_data/camoufox

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/trawl.service
[Unit]
Description=TRAWL self-hosted scraping engine
After=network-online.target redis-server.service
Wants=network-online.target
Requires=redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/trawl
EnvironmentFile=/etc/trawl.env
ExecStart=/usr/local/bin/bun run apps/api/src/index.ts
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now trawl
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
