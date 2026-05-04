#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: glifocat
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/qwibitai/nanoclaw

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  curl \
  git \
  ca-certificates \
  gnupg \
  build-essential \
  iptables
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Enabling corepack (pnpm version pinned by repo's package.json)"
# Don't pre-pin to pnpm@latest — the repo's package.json declares its own
# packageManager. Corepack will fetch that version on first `pnpm install`.
# COREPACK_ENABLE_DOWNLOAD_PROMPT=0 skips the interactive Y/n prompt.
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
$STD corepack enable
msg_ok "Corepack enabled (pnpm will be fetched on first install)"

setup_docker

msg_info "Creating nanoclaw user"
$STD useradd --create-home --shell /bin/bash --comment "NanoClaw bot user" nanoclaw
$STD usermod -aG docker nanoclaw
$STD loginctl enable-linger nanoclaw
msg_ok "Created nanoclaw user (UID $(id -u nanoclaw), groups: $(id -nG nanoclaw))"

msg_info "Cloning NanoClaw v2 repository"
$STD su - nanoclaw -c "git clone https://github.com/qwibitai/nanoclaw.git /home/nanoclaw/nanoclaw"
msg_ok "Cloned NanoClaw"

msg_info "Installing Node dependencies"
$STD su - nanoclaw -c "export COREPACK_ENABLE_DOWNLOAD_PROMPT=0; cd /home/nanoclaw/nanoclaw && pnpm install --prefer-frozen-lockfile"
msg_ok "Installed Node dependencies"

msg_info "Building NanoClaw"
$STD su - nanoclaw -c "cd /home/nanoclaw/nanoclaw && pnpm run build"
msg_ok "Built NanoClaw"

motd_ssh
customize
cleanup_lxc
