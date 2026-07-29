#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: kauezatarin
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.spigotmc.org/

APP="SpigotMC"
var_tags="${var_tags:-game;minecraft;server}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
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
  
  if [[ ! -d /opt/spigotmc ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping SpigotMC service"
  systemctl stop spigotmc
  msg_ok "Stopped SpigotMC service"
  
  msg_info "Backing up SpigotMC folder"
  cp -r /opt/spigotmc /opt/spigotmc_backup
  msg_ok "Backed up to /opt/spigotmc_backup"
  
  msg_info "Building new SpigotMC jar (Patience)"
  mkdir -p /opt/spigotmc-build
  cd /opt/spigotmc-build
  wget -qO BuildTools.jar https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar
  
  MC_VERSION=${MC_VERSION:-latest}
  JAVA_VERSION=25
  if [[ "$MC_VERSION" =~ ^1\.(17|18|19|20)(\.|$) ]]; then
      JAVA_VERSION=21
  fi
  JAVA_VERSION="${JAVA_VERSION}" setup_java
  
  java -jar BuildTools.jar --rev $MC_VERSION >/dev/null 2>&1
  mv spigot-*.jar /opt/spigotmc/spigot.jar
  rm -rf /opt/spigotmc-build
  msg_ok "Built new SpigotMC jar"
  
  msg_info "Starting SpigotMC service"
  systemctl start spigotmc
  msg_ok "Started SpigotMC service"
  
  msg_ok "Updated Successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following IP:${CL}"
echo -e "${GATEWAY}${BGN} ${IP}:25565 ${CL}"
echo -e "${INFO}${YW} RCON Password has been randomly generated and saved in /opt/spigotmc/server.properties.${CL}"
echo -e "${INFO}${YW} Samba Share: \\\\${IP}\SpigotMC (User: root / Pass: spigot)${CL}"
