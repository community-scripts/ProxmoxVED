#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/vllm-project/vllm

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
  python3-dev
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv
setup_hwaccel

msg_info "Installing vLLM (Patience)"
$STD uv venv --python 3.12 /opt/vllm
$STD uv pip install --python /opt/vllm/bin/python vllm
cat <<EOF >~/.vllm
$(get_latest_github_release "vllm-project/vllm")
EOF
msg_ok "Installed vLLM"

msg_info "Configuring vLLM"
mkdir -p /opt/vllm/models
cat <<EOF >/opt/vllm/vllm.env
VLLM_MODEL=Qwen/Qwen2.5-0.5B-Instruct
VLLM_HOST=0.0.0.0
VLLM_PORT=8000
HF_HOME=/opt/vllm/models
HF_TOKEN=
EOF
msg_ok "Configured vLLM"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/vllm.service
[Unit]
Description=vLLM OpenAI-Compatible Inference Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/vllm
EnvironmentFile=/opt/vllm/vllm.env
ExecStart=/opt/vllm/bin/vllm serve \${VLLM_MODEL} --host \${VLLM_HOST} --port \${VLLM_PORT}
Restart=on-failure
RestartSec=10
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now vllm
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
