#!/usr/bin/env bash
# Copyright (c) 2026
# Author: Simon Friedrich
# License: MIT
# Source: https://forgejo.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# -------------------------------------------------
# App-specific input (MUST be before variables)
# -------------------------------------------------
if [[ -z "$var_forgejo_instance" ]]; then
  read -rp "Forgejo Instance URL (e.g. https://code.forgejo.org): " var_forgejo_instance
fi

if [[ -z "$var_forgejo_runner_token" ]]; then
  read -rp "Forgejo Runner Registration Token: " var_forgejo_runner_token
  echo
fi

if [[ -z "$var_forgejo_instance" || -z "$var_forgejo_runner_token" ]]; then
  echo "❌ Forgejo instance URL and runner token are required."
  exit 1
fi

export FORGEJO_INSTANCE="$var_forgejo_instance"
export FORGEJO_RUNNER_TOKEN="$var_forgejo_runner_token"

msg_info "Installing dependencies"
$STD apt-get install -y \
  curl jq gnupg git wget ca-certificates \
  podman podman-docker
msg_ok "Dependencies installed"

msg_info "Enabling Podman socket"
systemctl enable --now podman.socket
msg_ok "Podman socket enabled"

# -------------------------------------------------
# Architecture
# -------------------------------------------------
RAW_ARCH=$(uname -m)
ARCH=$(echo "$RAW_ARCH" | sed 's/x86_64/amd64/;s/aarch64/arm64/')
msg_info "Detected architecture: $ARCH"

# -------------------------------------------------
# Fetch latest Forgejo Runner version
# -------------------------------------------------
msg_info "Fetching latest Forgejo Runner release"
RUNNER_VERSION=$(
  curl -fsSL https://data.forgejo.org/api/v1/repos/forgejo/runner/releases/latest |
  jq -r .name | sed 's/^v//'
)

[[ -z "$RUNNER_VERSION" ]] && {
  msg_error "Unable to determine Forgejo Runner version"
  exit 1
}

msg_ok "Forgejo Runner v${RUNNER_VERSION}"

# -------------------------------------------------
# Download Runner
# -------------------------------------------------
FORGEJO_URL="https://code.forgejo.org/forgejo/runner/releases/download/v${RUNNER_VERSION}/forgejo-runner-${RUNNER_VERSION}-linux-${ARCH}"

msg_info "Downloading Forgejo Runner"
wget -q -O /usr/local/bin/forgejo-runner "$FORGEJO_URL"
chmod +x /usr/local/bin/forgejo-runner
msg_ok "Runner installed"

# -------------------------------------------------
# Signature verification
# -------------------------------------------------
msg_info "Verifying signature"
wget -q -O /tmp/forgejo-runner.asc "${FORGEJO_URL}.asc"

GPG_KEY="EB114F5E6C0DC2BCDD183550A4B61A2DC5923710"
if ! gpg --list-keys "$GPG_KEY" >/dev/null 2>&1; then
  gpg --keyserver hkps://keys.openpgp.org --recv "$GPG_KEY" >/dev/null 2>&1
fi

gpg --verify /tmp/forgejo-runner.asc /usr/local/bin/forgejo-runner >/dev/null 2>&1 \
  && msg_ok "Signature valid" \
  || { msg_error "Signature verification failed"; exit 1; }

# -------------------------------------------------
# Runner registration
# -------------------------------------------------
msg_info "Registering Forgejo Runner"

export DOCKER_HOST="unix:///run/podman/podman.sock"

forgejo-runner register \
  --instance "$FORGEJO_INSTANCE" \
  --token "$FORGEJO_RUNNER_TOKEN" \
  --name "$HOSTNAME" \
  --labels "linux-${ARCH}:docker://node:20-bookworm" \
  --no-interactive

msg_ok "Runner registered"

# -------------------------------------------------
# systemd service
# -------------------------------------------------
msg_info "Creating systemd service"

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

systemctl daemon-reload
systemctl enable --now forgejo-runner
msg_ok "Forgejo Runner service enabled"

motd_ssh
customize
cleanup_lxc