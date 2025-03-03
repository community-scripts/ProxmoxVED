#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

APP="BabyBuddy"
var_disk="5"
var_cpu="2"
var_ram="2048"
var_os="debian"
var_version="12"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  if [[ ! -d /opt/babybuddy ]]; then msg_error "No ${APP} Installation Found!"; exit; fi
  RELEASE=$(curl -s https://api.github.com/repos/xxxxx/xxxxx/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
	exit
fi
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} Setup should be reachable by going to the following URL.
		 but first, you need to edit the influxDB connection!
         ${BL}http://${IP}:8080${CL} \n"