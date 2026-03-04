#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAI

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
  ca-certificates \
  jq \
  gpg \
  pciutils
msg_ok "Installed Dependencies"

msg_info "Installing Docker"

$STD apt update
$STD apt install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat <<EOF >/etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

$STD apt update
$STD apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable -q --now docker
msg_ok "Installed Docker"

fetch_and_deploy_gh_release "localai" "mudler/LocalAI" "singlefile" "latest" "/opt/localai-bin" "local-ai-v*-linux-amd64"

msg_info "Installing LocalAI Binary"
localai_binary="$(find /opt/localai-bin -maxdepth 1 -type f -name 'local-ai-v*-linux-amd64' | sort | tail -n1)"
if [[ -z "$localai_binary" ]]; then
  msg_error "Unable to locate downloaded LocalAI linux-amd64 binary"
  exit 1
fi
install -m 755 "$localai_binary" /usr/local/bin/local-ai
if [[ -f ~/.localai ]]; then
  tr -d '\n' <~/.localai >/opt/localai_version.txt
fi
msg_ok "Installed LocalAI Binary"

if [[ -e /dev/kfd ]] || lspci -nn 2>/dev/null | grep -qE '\[1002:|\[1022:'; then
  msg_info "Installing ROCm"
  export DEBIAN_FRONTEND=noninteractive

  apt_get_retry_install() {
    local args="$*"
    local attempt
    for attempt in 1 2 3; do
      apt-get -qq -o Dpkg::Use-Pty=0 -o Acquire::Retries=5 -o Acquire::http::No-Cache=true -o Acquire::https::No-Cache=true update >/dev/null 2>&1 && \
        apt-get -qq -o Dpkg::Use-Pty=0 -o Acquire::Retries=5 install -y $args >/dev/null 2>&1 && return 0
      apt-get clean || true
      rm -rf /var/lib/apt/lists/* || true
      if [[ "$attempt" -lt 3 ]]; then
        sleep 5
      fi
    done
    return 1
  }

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg
  chmod 644 /etc/apt/keyrings/rocm.gpg

  cat <<EOF >/etc/apt/sources.list.d/rocm.list
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2/ubuntu noble main
EOF

  cat <<EOF >/etc/apt/preferences.d/rocm-pin-600
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

  apt_get_retry_install --fix-missing --no-install-recommends rocm
  msg_ok "Installed ROCm"
  if [[ ! -e /dev/kfd ]]; then
    msg_warn "ROCm installed without /dev/kfd; add /dev/kfd passthrough and restart container for GPU acceleration"
  fi
fi

mkdir -p /etc/localai /var/lib/localai/models
cat <<EOF >/etc/localai/localai.env
MODELS_PATH=/var/lib/localai/models
EOF
chmod 644 /etc/localai/localai.env

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/localai.service
[Unit]
Description=LocalAI Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/lib/localai
EnvironmentFile=/etc/localai/localai.env
ExecStart=/usr/local/bin/local-ai
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now localai
msg_ok "Created Service"

if ! systemctl is-active -q localai; then
  msg_error "Failed to start LocalAI service"
  exit 1
fi
msg_ok "Started LocalAI"

motd_ssh
customize
cleanup_lxc
