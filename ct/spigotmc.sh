#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: kauezatarin
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
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
  
  if ! pct exec "$CTID" -- test -d /opt/spigotmc; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping SpigotMC service"
  pct exec "$CTID" -- systemctl stop spigotmc
  msg_ok "Stopped SpigotMC service"
  
  msg_info "Backing up SpigotMC folder"
  pct exec "$CTID" -- bash -c 'tar -czf /root/spigotmc_backup_$(date +%Y%m%d_%H%M%S).tar.gz -C /opt spigotmc'
  msg_ok "Backed up to /root/"
  
  MC_VERSION=$(whiptail --inputbox "Which SpigotMC version would you like to update to? (e.g. 1.20.4, 26.2)" 10 58 "latest" --title "SpigotMC Update" 3>&1 1>&2 2>&3 || echo "latest")
  
  msg_info "Building new SpigotMC jar (Patience)"
  pct exec "$CTID" -- bash -c "
    mkdir -p /opt/spigotmc-build
    cd /opt/spigotmc-build
    wget -qO BuildTools.jar https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar
    
    JAVA_VERSION=25
    if [[ \"\$MC_VERSION\" =~ ^1\.(17|18|19|20)(\.|$) ]]; then
        JAVA_VERSION=21
    fi
    apt update >/dev/null 2>&1
    apt install -y zulu\${JAVA_VERSION}-jdk >/dev/null 2>&1
    
    java -jar BuildTools.jar --rev \$MC_VERSION >/dev/null 2>&1
    mv spigot-*.jar /opt/spigotmc/spigot.jar
    rm -rf /opt/spigotmc-build
  "
  msg_ok "Built new SpigotMC jar"
  
  msg_info "Starting SpigotMC service"
  pct exec "$CTID" -- systemctl start spigotmc
  msg_ok "Started SpigotMC service"
  
  msg_ok "Updated Successfully!"
  exit
}

start
if [ -z "${MC_VERSION:-}" ]; then
  MC_VERSION=$(whiptail --inputbox "Which SpigotMC version would you like to install? (e.g. 1.20.4, 26.2)" 10 58 "latest" --title "SpigotMC Version" 3>&1 1>&2 2>&3 || echo "latest")
fi
export MC_VERSION
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following IP:${CL}"
echo -e "${GATEWAY}${BGN} ${IP}:25565 ${CL}"
echo -e "${INFO}${YW} RCON Password has been randomly generated and saved in /opt/spigotmc/server.properties.${CL}"
echo -e "${INFO}${YW} Samba Share: \\\\${IP}\SpigotMC (User: root / Pass: spigot)${CL}"
