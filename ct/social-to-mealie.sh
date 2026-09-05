#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/Gulivert/ProxmoxVE/feat/social-to-mealie"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

APP="Social Media to Mealie"
var_tags="recipe;media;ai"
var_cpu="2"
var_ram="4096"
var_disk="8"
var_os="debian"
var_version="12"
var_unprivileged="1"
var_hostname="social-to-mealie"

function header_info {
clear
cat <<"EOF"
   ____             _       _   _____       __  __            _ _      
  / ___|  ___   ___(_) __ _| | |_   _|__   |  \/  | ___  __ _| (_) ___ 
  \___ \ / _ \ / __| |/ _` | |   | |/ _ \  | |\/| |/ _ \/ _` | | |/ _ \
   ___) | (_) | (__| | (_| | |   | | (_) | | |  | |  __/ (_| | | |  __/
  |____/ \___/ \___|_|\__,_|_|   |_|\___/  |_|  |_|\___|\__,_|_|_|\___|

EOF
echo -e "${BL}By GerardPolloRebozado${CL}\n"
}
header_info
echo -e "\n"
var_install="social-to-mealie-install"
color
catch_errors

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4000${CL}\n"
echo -e "${INFO}${YW} ${APP} requires additional configuration before starting."
echo -e "${TAB}${YW} Edit the environment file in the container console using:"
echo -e "${TAB}${YW}   nano /opt/social-to-mealie/.env"
echo -e "${TAB}${YW} Then restart the service with: systemctl restart social-to-mealie${CL}"
