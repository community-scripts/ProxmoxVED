#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/arm64-dev-build/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rogerfar/rdt-client

APP="RDTClient"
var_tags="${var_tags:-torrent}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/rdtc/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "rdt-client" "rogerfar/rdt-client"; then
    msg_info "Stopping Service"
    systemctl stop rdtc
    msg_ok "Stopped Service"

    msg_info "Creating backup"
    mkdir -p /opt/rdtc-backup
    cp -R /opt/rdtc/appsettings.json /opt/rdtc-backup/
    msg_ok "Backup created"

    fetch_and_deploy_gh_release "rdt-client" "rogerfar/rdt-client" "prebuild" "latest" "/opt/rdtc" "RealDebridClient.zip"
    cp -R /opt/rdtc-backup/appsettings.json /opt/rdtc/
    if dpkg-query -W dotnet-sdk-8.0 >/dev/null 2>&1; then
      $STD apt remove --purge -y dotnet-sdk-8.0
      ensure_dependencies aspnetcore-runtime-9.0
    fi
    rm -rf /opt/rdtc-backup

    msg_info "Starting Service"
    systemctl start rdtc
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

function update_script_arm64() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/rdtc/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "rdt-client" "rogerfar/rdt-client"; then
    msg_info "Stopping Service"
    systemctl stop rdtc
    msg_ok "Stopped Service"

    msg_info "Updating .NET Runtime"
    rm -rf /usr/share/dotnet /usr/bin/dotnet
    $STD apt-get install -y libc6 libgcc-s1 libgssapi-krb5-2 liblttng-ust1 libssl3 libstdc++6 zlib1g libicu76
    curl -fsSL -o /tmp/dotnet.tar.gz "https://download.visualstudio.microsoft.com/download/pr/6f79d99b-dc38-4c44-a549-32329419bb9f/a411ec38fb374e3a4676647b236ba021/dotnet-sdk-9.0.100-linux-arm64.tar.gz"
    mkdir -p /usr/share/dotnet
    tar -zxf /tmp/dotnet.tar.gz -C /usr/share/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
    rm -f /tmp/dotnet.tar.gz
    msg_ok "Updated .NET Runtime"
  fi
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6500${CL}"
