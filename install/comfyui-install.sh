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
skip_user_config="${skip_user_config:-N}"
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




# Current configuration variables
current_settings_info() {
  echo
  echo "${TAB3}${TAB3}Current configuration summary:"
  echo "${TAB3}${TAB3}-------------------------------"
  echo "${TAB3}${TAB3}${TAB3}ComfyUI version            : ${comfyui_version}"
  echo "${TAB3}${TAB3}${TAB3}GPU                        : ${gpu_type}"
  echo "${TAB3}${TAB3}${TAB3}Python version (uv)        : ${python_version_uv}"
  echo "${TAB3}${TAB3}${TAB3}Port                       : ${port_arg}"
  echo "${TAB3}${TAB3}${TAB3}ComfyUI python args        : ${comfyui_python_args}"
  echo "${TAB3}${TAB3}${TAB3}ComfyUI Manager            : ${comfyui_manager_enabled}"
  echo "${TAB3}${TAB3}${TAB3}ComfyUI Manager Version    : ${comfyui_manager_version}"
  echo "${TAB3}${TAB3}${TAB3}Preview ExecStart command  : main.py ${comfyui_python_net_args} ${comfyui_python_port_args} ${comfyui_python_args}"
  echo
}



# GPU selection
select_gpu_type() {
  # Determine default based on current gpu_type
  case "${gpu_type}" in
    "None")   default_choice=1 ;;
    "NVIDIA") default_choice=2 ;;
    "AMD")    default_choice=3 ;;
    "Intel")  default_choice=4 ;;
    *)        default_choice=1 ;;  # fallback default
  esac

  while true; do
    echo
    echo "${TAB3}${TAB3}Choose the GPU type for ComfyUI:"
    echo "${TAB3}${TAB3}-------------------------------"
    echo "${TAB3}${TAB3}${TAB3}  1. None"
    echo "${TAB3}${TAB3}${TAB3}  2. NVIDIA"
    echo "${TAB3}${TAB3}${TAB3}  3. AMD"
    echo "${TAB3}${TAB3}${TAB3}  4. Intel"
    echo
    read -rp "${TAB3}${TAB3}${TAB3}Enter your choice [1-4] (Current: ${default_choice}. ${gpu_type}): " gpu_choice
    gpu_choice=${gpu_choice:-$default_choice}
    case "$gpu_choice" in
      1) gpu_type="None"; break ;;
      2) gpu_type="NVIDIA"; break ;;
      3) gpu_type="AMD"; break ;;
      4) gpu_type="Intel"; break ;;
      *) echo "${TAB3}${TAB3}${TAB3}${TAB3}Invalid choice. Please enter a number between 1 and 4." ;;
    esac
  done
}



# ComfyUI version
set_comfyui_version() {
  while true; do
    echo
    read -re -i "${comfyui_version}" -p  "${TAB3}${TAB3}Enter ComfyUI version (e.g. v0.3.49 or 'latest') [Current: ${comfyui_version}]: " input_version
    input_version=${input_version:-$comfyui_version}
    if [[ "$input_version" == "latest" || "$input_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      comfyui_version="$input_version"
      break
    else
      echo "${TAB3}${TAB3}${TAB3}${TAB3}Invalid input. Use 'latest' or a version like v0.3.49."
    fi
  done
}



# Python version
set_python_version() {
  read -re -i "${python_version_uv}" -p "${TAB3}${TAB3}Enter Python version (uv) [Current: ${python_version_uv}]: " input_python
  python_version_uv=${input_python:-$python_version_uv}
}



# Port number
set_port_number() {
  while true; do
    echo
    read -re -i "${port_arg}" -p "${TAB3}${TAB3}Enter port number [Current: ${port_arg}]: " input_port
    input_port=${input_port:-$port_arg}
    if [[ "$input_port" =~ ^[0-9]+$ ]]; then
      port_arg="$input_port"
      comfyui_python_port_args="--port ${port_arg}"
      break
    else
      echo "${TAB3}${TAB3}${TAB3}${TAB3}Invalid port. Must be a number."
    fi
  done
}



# ComfyUI arguments
set_comfyui_args() {
  read -re -i "${comfyui_python_args}" -p "${TAB3}${TAB3}Enter ComfyUI python args. (e.g. --gpu-only) [Current: ${comfyui_python_args}]: " input_args
  comfyui_python_args=${input_args}
}



# Set ComfyUI manager
set_comfyui_manager() {
  while true; do
    echo
    read -re -i "${comfyui_manager_enabled}" -p "${TAB3}${TAB3}Enable ComfyUI-Manager? [Y/n] (Current: ${comfyui_manager_enabled}): " input_manager
    input_manager=${input_manager:-$comfyui_manager_enabled}
    case "${input_manager,,}" in
      [Yy])
        comfyui_manager_enabled="Y"
        break
        ;;
      [Nn])
        comfyui_manager_enabled="N"
        break
        ;;
      *)
        echo "${TAB3}${TAB3}${TAB3}Please enter Y/y or N/n."
        ;;
    esac
  done
}



# ComfyUI Manager version
set_comfyui_manager_version() {
  if [[ "${comfyui_manager_enabled}" == "Y" ]]; then
    while true; do
      echo
      read -re -i "${comfyui_manager_version}" -p  "${TAB3}${TAB3}Enter ComfyUI Manager version (e.g. 3.35 or 'latest' <Note:latest='git clone repo'>) [Current: ${comfyui_manager_version}]: " input_version
      input_version=${input_version:-$comfyui_manager_version}
      if [[ "$input_version" == "latest" || "$input_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        comfyui_manager_version="$input_version"
        break
      else
        echo "${TAB3}${TAB3}${TAB3}${TAB3}Invalid input. Use 'latest' or a version like 3.35."
      fi
    done
  fi
}



# Installation ComfyUI Manager
install_comfyui_manager() {
  # Define the target directory
  local custom_nodes_dir="${app_path}/custom_nodes"
  local comfyui_manager_dir="${custom_nodes_dir}/comfyui-manager"

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
}



# Confirm configuration
confirm_configuration() {
  while true; do
    echo
    echo
    read -rp "${TAB3}${TAB3}${TAB3}Do you want to keep this configuration? [Y/n]: " CONFIG_CONFIRM
    CONFIG_CONFIRM=${CONFIG_CONFIRM:-y}

    case "$CONFIG_CONFIRM" in
      [Yy])
        echo "${TAB3}${TAB3}${TAB3}${TAB3}Current configuration accepted."
        break
        ;;
      [Nn])
        echo "${TAB3}${TAB3}${TAB3}${TAB3}Switching to advanced configuration..."
        break
        ;;
      *)
        echo "${TAB3}${TAB3}${TAB3}${TAB3}Please enter Y/y or N/n."
        ;;
    esac
  done
}



# Division line
division_line() {
  echo
  echo
  echo "${TAB3}=============================================================="
  echo
}



# Advanced configuration wrapper
advanced_config() {
  select_gpu_type
  division_line
  set_comfyui_version
  division_line
  set_python_version
  division_line
  set_port_number
  division_line
  set_comfyui_args
  division_line
  set_comfyui_manager
  division_line
  set_comfyui_manager_version
}


# Notification
notification() {
  echo
  echo "You can always skip manual configuration by using dynamic variables. For example:"
  echo
  echo "skip_user_config=\"Y|y|N|n\" \\"
  echo "comfyui_version=\"latest|v0.3.49\" \\"
  echo "python_version_uv=\"${python_version_uv}\" \\"
  echo "port_arg=\"${port_arg}\" \\"
  echo "comfyui_python_args=\"${comfyui_python_args}\" \\"
  echo "gpu_type=\"None|NVIDIA|AMD|Intel\" \\"
  echo "comfyui_python_index_url_nvidia=\"${comfyui_python_index_url_nvidia}\" \\"
  echo "comfyui_python_index_url_amd=\"${comfyui_python_index_url_amd}\" \\"
  echo "comfyui_python_index_url_intel=\"${comfyui_python_index_url_intel}\" \\"
  echo "comfyui_manager_enabled=\"Y|y|N|n\" \\"
  echo "comfyui_manager_version=\"latest|3.35\" \\"
  echo "bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/comfyui.sh)\""
  echo
}


# Notification2
notification2() {
  echo
  echo "You can reuse the same configuration by defining dynamic variables, using the following command:"
  echo
  echo "skip_user_config=\"Y\" \\"
  echo "comfyui_version=\"${comfyui_version}\" \\"
  echo "python_version_uv=\"${python_version_uv}\" \\"
  echo "port_arg=\"${port_arg}\" \\"
  echo "comfyui_python_args=\"${comfyui_python_args}\" \\"
  echo "gpu_type=\"${gpu_type}\" \\"
  gpu_type_noti="${gpu_type,,}"
  if [[ "$gpu_type_noti" == "nvidia" ]]; then
    echo "comfyui_python_index_url_nvidia=\"${comfyui_python_index_url_nvidia}\" \\"
  elif [[ "$gpu_type_noti" == "amd" ]]; then
    echo "comfyui_python_index_url_amd=\"${comfyui_python_index_url_amd}\" \\"
  elif [[ "$gpu_type_noti" == "intel" ]]; then
    echo "comfyui_python_index_url_intel=\"${comfyui_python_index_url_intel}\" \\"
  fi
  echo "comfyui_manager_enabled=\"${comfyui_manager_enabled}\" \\"
  echo "comfyui_manager_version=\"${comfyui_manager_version}\" \\"
  echo "bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/comfyui.sh)\""
  echo
}



# User configuration menu
division_line
notification
division_line
if ! [[ "$skip_user_config" =~ ^[Yy]$ ]]; then
  # Basic config
  msg_info "${application_name} configuration"
  division_line
  select_gpu_type
  # Advanced config loop until config_confirm_clean is "n"
  while true; do
    division_line
    current_settings_info
    confirm_configuration
    division_line
    config_confirm_clean=${CONFIG_CONFIRM,,}
    if [[ "$config_confirm_clean" == "n" ]]; then
      # Advanced config
      advanced_config
    else
      break
    fi
  done
  msg_ok "${application_name} configuration"
  division_line
  notification2
  division_line
  else
    echo "Skipping user config"
    division_line
fi



# Display current configuration variables
echo -e "${CM}${BOLD}${DGN}Skip User Config           : ${BGN}${skip_user_config}${CL}"
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
  install_comfyui_manager
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


