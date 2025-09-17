#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: jdacode
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/comfyanonymous/ComfyUI

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

application_name="${APPLICATION}"
comfyui_path="/opt/${application_name}"
comfyui_python_path="${comfyui_path}/venv/bin/python"
comfyui_port_arg="8188"
comfyui_python_version_uv="3.12"
comfyui_python_args="--cpu"
comfyui_index_url_nvidia="https://download.pytorch.org/whl/cu128"
comfyui_index_url_amd="https://download.pytorch.org/whl/rocm6.3"
comfyui_index_url_intel="https://download.pytorch.org/whl/xpu"

echo
echo "${TAB3}Choose the GPU type for ComfyUI:"
echo "${TAB3}[1]-None  [2]-NVIDIA  [3]-AMD  [4]-Intel"
read -rp "${TAB3}Enter your choice [1-4] (default: 1): " gpu_choice
gpu_choice=${gpu_choice:-1}
case "$gpu_choice" in
1) comfyui_gpu_type="none";;
2) comfyui_gpu_type="nvidia";;
3) comfyui_gpu_type="amd";;
4) comfyui_gpu_type="intel";;
*) comfyui_gpu_type="none"; echo "${TAB3}Invalid choice. Defaulting to ${comfyui_gpu_type}." ;;
esac
echo

msg_info "Installing Dependencies"
$STD apt-get install -y \
  git
msg_ok "Installed Dependencies"

msg_info "Setup uv"
PYTHON_VERSION="${comfyui_python_version_uv}" setup_uv
msg_ok "Setup uv"

fetch_and_deploy_gh_release "${application_name}" "comfyanonymous/ComfyUI" "tarball" "latest" "${comfyui_path}"

msg_info "Python dependencies"
$STD uv venv "${comfyui_path}/venv"
if [[ "${comfyui_gpu_type,,}" == "nvidia" ]]; then
  $STD uv pip install \
      torch \
      torchvision \
      torchaudio \
      --extra-index-url "${comfyui_index_url_nvidia}" \
      --python="${comfyui_python_path}"
elif [[ "${comfyui_gpu_type,,}" == "amd" ]]; then
  $STD uv pip install \
      torch \
      torchvision \
      torchaudio \
      --index-url "${comfyui_index_url_amd}" \
      --python="${comfyui_python_path}"
elif [[ "${comfyui_gpu_type,,}" == "intel" ]]; then
  $STD uv pip install \
      torch \
      torchvision \
      torchaudio \
      --index-url "${comfyui_index_url_intel}" \
      --python="${comfyui_python_path}"
fi
$STD uv pip install -r "${comfyui_path}/requirements.txt" --python="${comfyui_python_path}"
msg_ok "Python dependencies"

msg_info "Install ${application_name} Manager"
comfyui_manager_dir="${comfyui_path}/custom_nodes/comfyui-manager"
git clone https://github.com/ltdrdata/ComfyUI-Manager "${comfyui_manager_dir}"
$STD uv pip install -r "${comfyui_manager_dir}/requirements.txt" --python="${comfyui_python_path}"
msg_ok "Installed ${application_name} Manager"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/"${application_name}".service
[Unit]
Description=${application_name} Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${comfyui_path}
ExecStart=${comfyui_python_path} ${comfyui_path}/main.py --listen --port ${comfyui_port_arg} ${comfyui_python_args}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now "${application_name}"
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
