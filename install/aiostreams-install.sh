#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MrNRod
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Viren070/AIOStreams | Docs: https://docs.aiostreams.viren070.me/

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
  python3 \
  make \
  g++ \
  git \
  jq
msg_ok "Installed Dependencies"

NODE_VERSION="24" setup_nodejs

msg_info "Resolving Latest Release"
AIOSTREAMS_REFS=$(git ls-remote --tags --sort=-v:refname https://github.com/Viren070/AIOStreams.git 2>/dev/null | grep -v '\^{}')
AIOSTREAMS_REF=$(head -n1 <<<"${AIOSTREAMS_REFS}")
AIOSTREAMS_COMMIT=$(awk '{print $1}' <<<"${AIOSTREAMS_REF}")
AIOSTREAMS_TAG=$(awk '{print $2}' <<<"${AIOSTREAMS_REF}" | sed 's|^refs/tags/||')
if [[ -z "${AIOSTREAMS_TAG}" || -z "${AIOSTREAMS_COMMIT}" ]]; then
  msg_error "Could not resolve the latest AIOStreams release tag via git ls-remote"
  exit 1
fi
msg_ok "Resolved Latest Release: ${AIOSTREAMS_TAG}"

fetch_and_deploy_gh_release "aiostreams" "Viren070/AIOStreams" "tarball" "${AIOSTREAMS_TAG}"

msg_info "Enabling Corepack"
corepack enable
msg_ok "Enabled Corepack"

msg_info "Configuring Application"
mkdir -p /opt/aiostreams/data
cp /opt/aiostreams/.env.sample /opt/aiostreams/.env
SECRET_KEY=$(openssl rand -hex 32)
sed -i "s|^BASE_URL=.*|BASE_URL=http://${LOCAL_IP}:3000|" /opt/aiostreams/.env
sed -i "s|^SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|" /opt/aiostreams/.env
sed -i "s|^# PORT=3000|PORT=3000|" /opt/aiostreams/.env
msg_ok "Configured Application"

msg_info "Building AIOStreams (Patience)"
cd /opt/aiostreams
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export NODE_OPTIONS="--max-old-space-size=3072"
$STD pnpm install --frozen-lockfile
$STD pnpm run build
unset NODE_OPTIONS
cp -r /opt/aiostreams/packages/server/src/static /opt/aiostreams/packages/server/dist/static
msg_ok "Built AIOStreams"

msg_info "Generating Version Metadata"
mkdir -p /opt/aiostreams/resources
AIOSTREAMS_VERSION=$(jq -r '.version' /opt/aiostreams/package.json)
AIOSTREAMS_DESC=$(jq -r '.description' /opt/aiostreams/package.json)
AIOSTREAMS_COMMIT_TIME=$(curl -fsSL "https://api.github.com/repos/Viren070/AIOStreams/commits/${AIOSTREAMS_COMMIT}" 2>/dev/null | jq -r '.commit.committer.date // empty') || true
[[ -z "${AIOSTREAMS_COMMIT_TIME}" || "${AIOSTREAMS_COMMIT_TIME}" == "null" ]] && AIOSTREAMS_COMMIT_TIME=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
cat <<EOF >/opt/aiostreams/resources/metadata.json
{
  "version": "${AIOSTREAMS_VERSION}",
  "description": $(jq -Rn --arg d "${AIOSTREAMS_DESC}" '$d'),
  "tag": "${AIOSTREAMS_TAG}",
  "channel": "stable",
  "commitHash": "${AIOSTREAMS_COMMIT:0:8}",
  "buildTime": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "commitTime": "${AIOSTREAMS_COMMIT_TIME}"
}
EOF
msg_ok "Generated Version Metadata"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/aiostreams.service
[Unit]
Description=AIOStreams
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/aiostreams
EnvironmentFile=/opt/aiostreams/.env
ExecStart=/usr/bin/node /opt/aiostreams/packages/server/dist/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now aiostreams
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
