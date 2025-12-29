#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: Dunky13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/cmintey/wishlist

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt install -y build-essential python3 openssl git caddy
msg_ok "Installed dependencies"

NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs
fetch_and_deploy_gh_release "wishlist" "cmintey/wishlist" "tarball"
LATEST_APP_VERSION=$(get_latest_github_release "cmintey/wishlist")

msg_info "Installing Wishlist"
cd /opt/wishlist || exit
cat <<EOF >/opt/wishlist/.env
  NODE_ENV=production
  BODY_SIZE_LIMIT=5000000
  ORIGIN="http://0.0.0.0:3280" # The URL your users will be connecting to
  TOKEN_TIME=72 # hours until signup and password reset tokens expire
  DEFAULT_CURRENCY=EUR
  MAX_IMAGE_SIZE=5000000 # 5 megabytes
EOF
$STD pnpm install
$STD pnpm svelte-kit sync
$STD pnpm prisma generate
$STD sed -i 's|/usr/src/app/|/opt/wishlist/|g' $(grep -rl '/usr/src/app/' /opt/wishlist)
export VERSION="${LATEST_APP_VERSION}" 
export SHA="${LATEST_APP_VERSION}" 
$STD pnpm run build
$STD pnpm prune --prod
$STD chmod +x /opt/wishlist/entrypoint.sh
msg_ok "Installed Wishlist"

mkdir -p /opt/wishlist/uploads
mkdir -p /opt/wishlist/data

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/wishlist.service
[Unit]
Description=Wishlist Service
After=network.target

[Service]
WorkingDirectory=/opt/wishlist
ExecStart=/usr/bin/env sh -c './entrypoint.sh'
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now wishlist
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
echo "Edit /opt/wishlist/.env to customize settings"
