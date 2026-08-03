#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ggml-org/llama.cpp

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y libgomp1
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "llama-cpp" "ggml-org/llama.cpp" "prebuild" "latest" "/opt/llama-cpp" "llama-*-bin-ubuntu-$(arch_resolve x64 arm64).tar.gz"

msg_info "Configuring llama.cpp"
chmod +x /opt/llama-cpp/llama-*
mkdir -p /opt/llama-cpp_data/models
cat <<EOF >/opt/llama-cpp.env
LLAMA_ARG_HOST=0.0.0.0
LLAMA_ARG_PORT=8080

# Model to serve. Either point at a local GGUF file:
#LLAMA_ARG_MODEL=/opt/llama-cpp_data/models/your-model.gguf
# ...or let llama-server pull one from Hugging Face on first start:
LLAMA_ARG_HF_REPO=ggml-org/gemma-3-1b-it-GGUF

LLAMA_CACHE=/opt/llama-cpp_data/models
LLAMA_ARG_CTX_SIZE=4096
LLAMA_ARG_N_GPU_LAYERS=0
EOF
chmod 600 /opt/llama-cpp.env
msg_ok "Configured llama.cpp"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/llama-cpp.service
[Unit]
Description=llama.cpp Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/llama-cpp
EnvironmentFile=/opt/llama-cpp.env
Environment=LD_LIBRARY_PATH=/opt/llama-cpp
ExecStart=/opt/llama-cpp/llama-server
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now llama-cpp
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
