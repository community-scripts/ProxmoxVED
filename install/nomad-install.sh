#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Alex Indigo (alexindigo)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Crosstalk-Solutions/project-nomad | https://www.projectnomad.us

# This script is adapted from Project N.O.M.A.D.'s install_nomad.sh
# to work within the ProxmoxVED infrastructure. Differences:
#  - Uses setup_docker() instead of get.docker.com
#  - Uses local tarball files instead of raw.githubusercontent.com URLs
#  - Port 80 instead of 8080
#  - setup_hwaccel for GPU driver installation

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

NOMAD_DIR="/opt/project-nomad"

# Accept license (interactive - legal requirement)
echo ""
echo "License Agreement & Terms of Use"
echo "__________________________"
echo ""
echo "Project N.O.M.A.D. is licensed under the Apache License 2.0."
echo "Full license: https://www.apache.org/licenses/LICENSE-2.0"
echo ""
read -p "I have read and accept License Agreement & Terms of Use (y/N)? " choice
case "$choice" in
  y|Y )
    echo "License accepted."
    ;;
  * )
    msg_error "License not accepted. Installation cannot continue."
    exit 1
    ;;
esac

# Install Docker
USE_DOCKER_REPO=true setup_docker

setup_hwaccel

if command -v nvidia-smi &>/dev/null || lspci 2>/dev/null | grep -qi nvidia; then
  if ! command -v nvidia-ctk &>/dev/null; then
    msg_info "Installing NVIDIA Container Toolkit"
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null || true
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list 2>/dev/null \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null 2>&1 || true
    $STD apt update 2>/dev/null || true
    $STD apt install -y nvidia-container-toolkit 2>/dev/null || true
    if command -v nvidia-ctk &>/dev/null; then
      nvidia-ctk runtime configure --runtime=docker 2>/dev/null || true
      systemctl restart docker 2>/dev/null || true
    fi
    msg_ok "NVIDIA Container Toolkit configured"
  fi
fi

# Download release tarball for version tracking and local files
fetch_and_deploy_gh_release "nomad" "Crosstalk-Solutions/project-nomad" "tarball"

msg_info "Setting up Nomad"
mkdir -p ${NOMAD_DIR}/storage/logs
cp /opt/nomad/install/management_compose.yaml ${NOMAD_DIR}/compose.yml
cp /opt/nomad/install/start_nomad.sh ${NOMAD_DIR}/start_nomad.sh
cp /opt/nomad/install/stop_nomad.sh ${NOMAD_DIR}/stop_nomad.sh
cp /opt/nomad/install/update_nomad.sh ${NOMAD_DIR}/update_nomad.sh
chmod +x ${NOMAD_DIR}/*.sh

# Configure compose file
APP_KEY=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c32)
DB_ROOT_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c13)
DB_USER_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c13)

sed -i "s|URL=replaceme|URL=http://${LOCAL_IP}|g" ${NOMAD_DIR}/compose.yml
sed -i "s|APP_KEY=replaceme|APP_KEY=${APP_KEY}|g" ${NOMAD_DIR}/compose.yml
sed -i "s|DB_PASSWORD=replaceme|DB_PASSWORD=${DB_USER_PASSWORD}|g" ${NOMAD_DIR}/compose.yml
sed -i "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}|g" ${NOMAD_DIR}/compose.yml
sed -i "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${DB_USER_PASSWORD}|g" ${NOMAD_DIR}/compose.yml
sed -i 's|"8080:8080"|"80:8080"|g' ${NOMAD_DIR}/compose.yml
msg_ok "Set up Nomad"

msg_info "Starting Nomad"
cd ${NOMAD_DIR}
$STD docker compose up -d
msg_ok "Started Nomad"

motd_ssh
customize
cleanup_lxc
