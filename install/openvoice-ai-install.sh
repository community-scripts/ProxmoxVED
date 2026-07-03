#!/usr/bin/env bash
# Copyright (c) 2026 OpenVoice AI contributors
# License: MIT
# Source: https://github.com/nikpottbecker/openvoice-ai

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y --no-install-recommends \
  asterisk \
  ca-certificates \
  curl \
  ffmpeg \
  git \
  jq \
  python3 \
  python3-pip \
  python3-venv \
  rsync \
  sox \
  unzip
msg_ok "Installed Dependencies"

msg_info "Installing OpenVoice AI"
git clone --depth 1 https://github.com/nikpottbecker/openvoice-ai.git /opt/phone-agent
cd /opt/phone-agent
bash scripts/install.sh
msg_ok "Installed OpenVoice AI"

motd_ssh
customize
cleanup_lxc
