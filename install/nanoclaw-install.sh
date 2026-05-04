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

setup_hwaccel

msg_info "Installing dependencies"
$STD apt install -y \
  sudo \
  ca-certificates \
  curl \
  git \
  acl
# acl provides setfacl, used by setup/service.ts as a fallback when the docker
# group membership isn't yet active in the current login session.
msg_ok "Installed dependencies"

msg_info "Creating nanoclaw user"
useradd -m -s /bin/bash nanoclaw
echo "nanoclaw ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/nanoclaw
chmod 440 /etc/sudoers.d/nanoclaw
loginctl enable-linger nanoclaw
msg_ok "Created nanoclaw user"

msg_info "Forwarding SSH key to nanoclaw"
# var_ssh="yes" lets the framework prompt for an authorized_key and write it
# to /root/.ssh/authorized_keys. Mirror it onto the nanoclaw user so the
# operator can SSH directly as nanoclaw with the same key, no password.
if [[ -s /root/.ssh/authorized_keys ]]; then
  install -d -o nanoclaw -g nanoclaw -m 700 /home/nanoclaw/.ssh
  install -o nanoclaw -g nanoclaw -m 600 /root/.ssh/authorized_keys /home/nanoclaw/.ssh/authorized_keys
  msg_ok "Forwarded SSH key to nanoclaw"
else
  msg_ok "No SSH key to forward (root has none)"
fi

msg_info "Cloning NanoClaw"
$STD sudo -u nanoclaw -H git clone https://github.com/qwibitai/nanoclaw.git /home/nanoclaw/nanoclaw-v2
msg_ok "Cloned NanoClaw"

msg_info "Writing setup MOTD"
cat <<'EOF' >/etc/update-motd.d/99-nanoclaw
#!/bin/sh
cat <<MOTD

  NanoClaw is staged at /home/nanoclaw/nanoclaw-v2

  Finish setup:
    su - nanoclaw
    cd ~/nanoclaw-v2
    bash nanoclaw.sh

  The wizard installs Node, pnpm, Docker, sets up the OneCLI vault,
  prompts for your Anthropic API key (or 'subscription' for Claude
  Code login), and starts the host service.

MOTD
EOF
chmod +x /etc/update-motd.d/99-nanoclaw
msg_ok "Wrote setup MOTD"

motd_ssh
customize
cleanup_lxc
