#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: dooha333
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/qwibitai/nanoclaw

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt install -y \
  sudo \
  ca-certificates \
  git \
  build-essential \
  systemd-container
msg_ok "Installed dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Creating nanoclaw user"
useradd -m -s /bin/bash nanoclaw
echo "nanoclaw ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/nanoclaw
chmod 440 /etc/sudoers.d/nanoclaw
loginctl enable-linger nanoclaw
msg_ok "Created nanoclaw user"

msg_info "Cloning NanoClaw"
$STD sudo -u nanoclaw -H git clone https://github.com/dooha333/nanoclaw /home/nanoclaw/nanoclaw
msg_ok "Cloned NanoClaw"

msg_info "Installing Claude CLI"
$STD sudo -u nanoclaw -H bash -lc 'curl -fsSL https://claude.ai/install.sh | bash' || true
msg_ok "Installed Claude CLI"

msg_info "Writing setup MOTD"
cat <<'EOF' >/etc/update-motd.d/99-nanoclaw
#!/bin/sh
cat <<MOTD

  NanoClaw is staged at /home/nanoclaw/nanoclaw

  Finish setup:
    su - nanoclaw
    cd ~/nanoclaw
    bash nanoclaw.sh

  The wizard installs Docker, sets up the OneCLI vault, prompts
  for your Anthropic API key (or 'subscription' for Claude Code
  login), and starts the host service.

MOTD
EOF
chmod +x /etc/update-motd.d/99-nanoclaw
msg_ok "Wrote setup MOTD"

motd_ssh
customize
cleanup_lxc
