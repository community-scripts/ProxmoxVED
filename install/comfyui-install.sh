#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: jdacode
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/comfyanonymous/ComfyUI

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os



# Installing Dependencies
msg_info "Installing Dependencies"
$STD apt-get install -y \
  git \
  nvtop
msg_ok "Installed Dependencies"



# Default configuration variables
# NO Configurable variables
application_name="${APPLICATION}"
app_path="/opt/${application_name}"
python_path="${app_path}/venv/bin/python"

# Configurable variables
# Versions
comfyui_version="${comfyui_version:-latest}"
python_version_uv="${python_version_uv:-3.12}"
# Python main.py arguments
port_arg="${port_arg:-8188}"
comfyui_python_net_args="--listen"
comfyui_python_port_args="--port ${port_arg}"
comfyui_python_args="${comfyui_python_args:---cpu}"
# GPU Settings
gpu_type="${gpu_type:-None}"
comfyui_python_index_url_nvidia="${comfyui_python_index_url_nvidia:-https://download.pytorch.org/whl/cu128}"
comfyui_python_index_url_amd="${comfyui_python_index_url_amd:-https://download.pytorch.org/whl/rocm6.3}"
comfyui_python_index_url_intel="${comfyui_python_index_url_intel:-https://download.pytorch.org/whl/xpu}"
# ComfyUI Manager
comfyui_manager_enabled="${comfyui_manager_enabled:-Y}"
comfyui_manager_version="${comfyui_manager_version:-latest}"



# Display current configuration variables
echo -e "${CM}${BOLD}${DGN}Application name           : ${BGN}${application_name}${CL}"
echo -e "${CM}${BOLD}${DGN}Application path           : ${BGN}${app_path}${CL}"
echo -e "${CM}${BOLD}${DGN}ComfyUI version            : ${BGN}${comfyui_version}${CL}"
echo -e "${CM}${BOLD}${DGN}GPU                        : ${BGN}${gpu_type}${CL}"
echo -e "${CM}${BOLD}${DGN}Port                       : ${BGN}${port_arg}${CL}"
echo -e "${CM}${BOLD}${DGN}ComfyUI Manager            : ${BGN}${comfyui_manager_enabled}${CL}"
echo -e "${CM}${BOLD}${DGN}ComfyUI Manager Version    : ${BGN}${comfyui_manager_version}${CL}"
echo -e "${CM}${BOLD}${DGN}Python version (uv)        : ${BGN}${python_version_uv}${CL}"
echo -e "${CM}${BOLD}${DGN}Python path (uv)           : ${BGN}${python_path}${CL}"
echo -e "${CM}${BOLD}${DGN}ComfyUI python args        : ${BGN}${comfyui_python_args}${CL}"
echo -e "${CM}${BOLD}${DGN}Pip Nvidia index-url       : ${BGN}${comfyui_python_index_url_nvidia}${CL}"
echo -e "${CM}${BOLD}${DGN}Pip AMD index-url          : ${BGN}${comfyui_python_index_url_amd}${CL}"
echo -e "${CM}${BOLD}${DGN}Pip Intel index-url        : ${BGN}${comfyui_python_index_url_intel}${CL}"
echo -e "${CM}${BOLD}${DGN}Preview ExecStart command  : ${BGN}main.py ${comfyui_python_net_args} ${comfyui_python_port_args} ${comfyui_python_args}${CL}"



# ComfyUI installation start from here!
# Installs uv
msg_info "Setup uv"
PYTHON_VERSION="${python_version_uv}" setup_uv
msg_ok "Setup uv"



# Comfy Version
msg_info "Setup ${application_name}"
if [[ "$comfyui_version" == "latest" ]]; then
  echo "Version is set to 'latest'; skipping version check."
  RELEASE=$(curl -fsSL https://api.github.com/repos/comfyanonymous/ComfyUI/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
else
  RELEASE="$comfyui_version"
fi
msg_ok "Setup ${application_name}"



# Comfy Release
msg_info "Installing ComfyUI version: ${RELEASE}"
curl -fsSL -o "${application_name}.zip" "https://github.com/comfyanonymous/ComfyUI/archive/refs/tags/${RELEASE}.zip"
unzip -q "${application_name}.zip"
# Remove v
CLEAN_RELEASE="${RELEASE//v/}"
# Move app to opt
mv "${application_name}-${CLEAN_RELEASE}/" "${app_path}"
echo "${RELEASE}" >/opt/"${application_name}"_version.txt
msg_ok "Installed ComfyUI version: ${RELEASE}"



# Dependencies
msg_info "Python dependencies"
$STD uv venv "${app_path}/venv"
gpu_type="${gpu_type,,}"
if [[ "$gpu_type" == "nvidia" ]]; then
  echo "NVIDIA GPU selected"
  $STD uv pip install \
      torch \
      torchvision \
      torchaudio \
      --extra-index-url "${comfyui_python_index_url_nvidia}" \
      --python="${python_path}"
elif [[ "$gpu_type" == "amd" ]]; then
  echo "AMD GPU selected"
  $STD uv pip install \
      torch \
      torchvision \
      torchaudio \
      --index-url "${comfyui_python_index_url_amd}" \
      --python="${python_path}"
elif [[ "$gpu_type" == "intel" ]]; then
  echo "Intel GPU selected"
  $STD uv pip install \
      torch \
      torchvision \
      torchaudio \
      --index-url "${comfyui_python_index_url_intel}" \
      --python="${python_path}"
else
  echo "No GPU selected"
fi
$STD uv pip install -r "${app_path}/requirements.txt" --python="${python_path}"
msg_ok "Python dependencies"



# Comfyui manager installation
if [[ "${comfyui_manager_enabled}" =~ ^[Yy]$ ]]; then
  msg_info "Install ${application_name} Manager"
  # Define the target directory
  custom_nodes_dir="${app_path}/custom_nodes"
  comfyui_manager_dir="${custom_nodes_dir}/comfyui-manager"

  # Check if the directory exists
  if [[ ! -d "${custom_nodes_dir}" ]]; then
    echo "${TAB3}${TAB3}${TAB3}Error: Directory not found: ${custom_nodes_dir}"
    return 1
  fi

  if [[ -d "${comfyui_manager_dir}" ]]; then
    echo "${TAB3}${TAB3}${TAB3}ComfyUI-Manager already exists. Skipping installation."
  else
    if [[ "${comfyui_manager_version}" == "latest" ]]; then
      # Clone the manager
      git clone https://github.com/ltdrdata/ComfyUI-Manager "${comfyui_manager_dir}"
    else
      # Download Release
      curl -fsSL -o "${comfyui_manager_version}.zip" "https://github.com/Comfy-Org/ComfyUI-Manager/archive/refs/tags/${comfyui_manager_version}.zip"
      # Unzip Release
      unzip -q "${comfyui_manager_version}.zip"
      # Move and rename
      mv "ComfyUI-Manager-${comfyui_manager_version}" "${comfyui_manager_dir}"
      # Clean up the zip file
      rm -f "${comfyui_manager_version}.zip"
    fi
    # Install Manager dependencies with uv
    $STD uv pip install -r "${comfyui_manager_dir}/requirements.txt" --python="${python_path}"
  fi
  msg_ok "Installed ${application_name} Manager"
else
  msg_error "No installed ${application_name} Manager"
fi



# Creating Service
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/"${application_name}".service
[Unit]
Description=${application_name} Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${app_path}
ExecStart=${python_path} ${app_path}/main.py ${comfyui_python_net_args} ${comfyui_python_port_args} ${comfyui_python_args}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now "${application_name}"
msg_ok "Created Service"



motd_ssh
customize



# Cleanup
msg_info "Cleaning up"
rm -f "${application_name}".zip
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"


