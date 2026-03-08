#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mcmonkeyprojects/SwarmUI

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
setup_deb822_repo \
  "microsoft" \
  "https://packages.microsoft.com/keys/microsoft-2025.asc" \
  "https://packages.microsoft.com/debian/13/prod/" \
  "trixie" \
  "main"
$STD apt install -y \
  git \
  libicu-dev \
  libssl-dev \
  dotnet-sdk-8.0 \
  aspnetcore-runtime-8.0
msg_ok "Installed Dependencies"

UV_PYTHON="3.11" setup_uv

fetch_and_deploy_gh_release "swarmui" "mcmonkeyprojects/SwarmUI" "tarball" "latest" "/opt/swarmui"

msg_info "Building SwarmUI"
cd /opt/swarmui
$STD dotnet build src/SwarmUI.csproj --configuration Release -o ./bin
msg_ok "Built SwarmUI"

msg_info "Setting up ComfyUI Backend"
mkdir -p /opt/swarmui/dlbackend
cd /opt/swarmui/dlbackend
$STD git clone https://github.com/comfyanonymous/ComfyUI.git comfy
cd comfy
$STD uv venv /opt/swarmui/dlbackend/comfy/venv
source /opt/swarmui/dlbackend/comfy/venv/bin/activate

PYTORCH_INDEX="https://download.pytorch.org/whl/cpu"
if nvidia_check_driver_installed && nvidia-smi &>/dev/null; then
    PYTORCH_INDEX="https://download.pytorch.org/whl/cu128"
    msg_info "NVIDIA GPU detected - installing PyTorch with CUDA 12.8 support"
elif amd_gpu_available; then
    PYTORCH_INDEX="https://download.pytorch.org/whl/rocm7.1"
    msg_info "AMD GPU detected - installing PyTorch with ROCm 7.1 support"
else
    msg_info "No GPU detected - installing PyTorch CPU version"
fi
$STD uv pip install torch torchvision torchaudio --index-url "$PYTORCH_INDEX"
$STD uv pip install -r requirements.txt
deactivate
msg_ok "Set up ComfyUI Backend"

msg_info "Creating Directories"
mkdir -p /opt/swarmui/Data
mkdir -p /opt/swarmui/Models
mkdir -p /opt/swarmui/Output
msg_ok "Created Directories"

msg_info "Configuring SwarmUI"
cat <<EOF >/opt/swarmui/Data/Settings.yaml
# SwarmUI Configuration
# For full documentation, see: https://github.com/mcmonkeyprojects/SwarmUI

# Network Settings
host: 0.0.0.0
port: 7801

# Paths
data_path: Data
model_path: Models
output_path: Output

# Backend Settings
backends:
  - type: comfyui
    name: local_comfyui
    path: dlbackend/comfy
    enabled: true

# Environment
environment: production
EOF
msg_ok "Configured SwarmUI"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/swarmui.service
[Unit]
Description=SwarmUI - Stable Diffusion WebUI
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/swarmui
ExecStart=/usr/bin/dotnet /opt/swarmui/bin/SwarmUI.dll
Environment=ASPNETCORE_URLS=http://0.0.0.0:7801
Environment=DOTNET_CONTENTROOT=/opt/swarmui
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now swarmui
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
