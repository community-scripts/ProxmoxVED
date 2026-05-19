#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: glifocat
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nanocoai/nanoclaw

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

msg_info "Installing Claude Code CLI"
# Native installer from Anthropic — drops the binary in ~/.local/bin and
# updates ~/.bashrc PATH. Pre-installing lets the wizard's auth + Claude-
# assisted error recovery work out of the box without a mid-wizard download.
$STD su - nanoclaw -c "curl -fsSL https://claude.ai/install.sh | bash"
msg_ok "Installed Claude Code CLI"

msg_info "Fetching NanoClaw release"
fetch_and_deploy_gh_release "nanoclaw" "nanocoai/nanoclaw" "tarball" "latest" "/home/nanoclaw/nanoclaw"
$STD chown -R nanoclaw:nanoclaw /home/nanoclaw/nanoclaw
msg_ok "Fetched NanoClaw release"

msg_info "Initializing git for /update-nanoclaw"
# /update-nanoclaw is git-based (needs an `upstream` remote + clean history
# to fetch/merge upstream changes). The tarball gives us source code but no
# git ancestry — init a repo here pointing at the deployed tag so the skill
# works out of the box.
NANOCLAW_VERSION=$(cat ~/.nanoclaw)
# fetch_and_deploy writes the bare version (e.g. "2.0.64") but the git tag
# is "v2.0.64" — normalize so we can pass either format here.
NANOCLAW_TAG="v${NANOCLAW_VERSION#v}"
$STD su - nanoclaw -c "cd /home/nanoclaw/nanoclaw && \
  git init -q && \
  git remote add upstream https://github.com/nanocoai/nanoclaw.git && \
  git fetch upstream --depth=1 refs/tags/${NANOCLAW_TAG}:refs/tags/${NANOCLAW_TAG} -q && \
  git reset refs/tags/${NANOCLAW_TAG}"
msg_ok "Initialized git tracking ${NANOCLAW_TAG}"

msg_info "Installing Node dependencies"
$STD su - nanoclaw -c "export COREPACK_ENABLE_DOWNLOAD_PROMPT=0; cd /home/nanoclaw/nanoclaw && pnpm install --prefer-frozen-lockfile"
msg_ok "Installed Node dependencies"

msg_info "Building NanoClaw"
$STD su - nanoclaw -c "cd /home/nanoclaw/nanoclaw && pnpm run build"
msg_ok "Built NanoClaw"

motd_ssh
customize
cleanup_lxc
