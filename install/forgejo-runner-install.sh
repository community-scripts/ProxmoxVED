#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Simon Friedrich
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://forgejo.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Get required configuration with sensible fallbacks for unattended mode
# These will show a warning if defaults are used
var_forgejo_instance=$(prompt_input_required \
  "Forgejo Instance URL:" \
  "${var_forgejo_instance:-https://codeberg.org}" \
  120 \
  "var_forgejo_instance")

var_forgejo_runner_token=$(prompt_input_required \
  "Forgejo Runner Registration Token:" \
  "${var_forgejo_runner_token:-REPLACE_WITH_YOUR_TOKEN}" \
  120 \
  "var_forgejo_runner_token")

export FORGEJO_INSTANCE="$var_forgejo_instance"
export FORGEJO_RUNNER_TOKEN="$var_forgejo_runner_token"

msg_info "Installing dependencies"
$STD apt install -y \
  git \
  podman podman-docker
msg_ok "Installed dependencies"

msg_info "Enabling Podman socket"
systemctl enable --now podman.socket
msg_ok "Enabled Podman socket"

msg_info "Installing Forgejo Runner"
RUNNER_VERSION=$(curl -fsSL https://data.forgejo.org/api/v1/repos/forgejo/runner/releases/latest | jq -r .name | sed 's/^v//')
curl -fsSL "https://code.forgejo.org/forgejo/runner/releases/download/v${RUNNER_VERSION}/forgejo-runner-${RUNNER_VERSION}-linux-amd64" -o /usr/local/bin/forgejo-runner
chmod +x /usr/local/bin/forgejo-runner
msg_ok "Installed Forgejo Runner"

msg_info "Registering Forgejo Runner"
export DOCKER_HOST="unix:///run/podman/podman.sock"
forgejo-runner register \
  --instance "$FORGEJO_INSTANCE" \
  --token "$FORGEJO_RUNNER_TOKEN" \
  --name "$HOSTNAME" \
  --labels "linux-amd64:docker://node:20-bookworm" \
  --no-interactive
msg_ok "Registered Forgejo Runner"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/forgejo-runner.service
[Unit]
Description=Forgejo Runner
Documentation=https://forgejo.org/docs/latest/admin/actions/
After=podman.socket
Requires=podman.socket

[Service]
User=root
WorkingDirectory=/root
Environment=DOCKER_HOST=unix:///run/podman/podman.sock
ExecStart=/usr/local/bin/forgejo-runner daemon
Restart=on-failure
RestartSec=10
TimeoutSec=0

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now forgejo-runner
msg_ok "Created Services"

# Show warning if any required values used fallbacks
show_missing_values_warning

motd_ssh
customize
cleanup_lxc
