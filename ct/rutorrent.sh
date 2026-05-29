#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trawis
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Novik/ruTorrent

APP="ruTorrent"
var_tags="${var_tags:-torrent;bittorrent;download}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

# Plugin catalogue — each entry: "slug|Display Label|default(on/off)"
PLUGIN_DEFS=(
  "autotools|AutoTools|on"
  "check_port|Check Port|on"
  "chunks|Chunks|on"
  "cookies|Cookies|on"
  "cpuload|CPU Load|on"
  "create|Create Torrent|on"
  "data|Data|on"
  "datadir|Data Dir|on"
  "diskspace|Disk Space|on"
  "edit|Edit Tracker|on"
  "erasedata|Erase Data|on"
  "extratio|Extra Ratio|on"
  "extsearch|External Search|on"
  "feeds|Feeds|on"
  "filedrop|File Drop|on"
  "geoip|GeoIP|on"
  "history|History|on"
  "httprpc|HTTP RPC|on"
  "ipad|iPad|on"
  "log_history|Log History|on"
  "loginmgr|Login Manager|on"
  "lookat|Look At|on"
  "mediainfo|Media Info|on"
  "ratio|Ratio|on"
  "ratiocolor|Ratio Color|on"
  "rpc|RPC|on"
  "rss|RSS|on"
  "rssurlrewrite|RSS URL Rewrite|on"
  "scheduler|Scheduler|on"
  "screenshots|Screenshots|on"
  "seedingtime|Seeding Time|on"
  "show_peers_like_wtorrent|Show Peers Like wTorrent|on"
  "source|Source|on"
  "spectrogram|Spectrogram|on"
  "theme|Theme|on"
  "tracklabels|Track Labels|on"
  "trackerstatus|Tracker Status|on"
  "trafic|Traffic|on"
  "unpack|Unpack|on"
  "xmpp|XMPP (broken: PHP 8 incompatible)|off"
  "_cloudflare|_cloudflare (Cloudflare scraper)|on"
  "_getdir|_getdir (Directory browser)|on"
  "_noty|_noty (Notifications v1)|on"
  "_noty2|_noty2 (Notifications v2)|on"
  "_task|_task (Task queue, required by create/unpack)|on"
  "dump|dump (broken: dumptorrent not in Debian 13 repos)|off"
  "throttle|throttle (broken: old rTorrent API)|off"
  "retrackers|Retrackers|on"
  "rutracker_check|RuTracker Check|on"
  "uploadeta|Upload ETA|on"
  "bulk_magnet|Bulk Magnet|on"
)

if [[ -z "${RUTORRENT_PLUGINS}" ]]; then
  # Username
  RUTORRENT_USER=$(whiptail --inputbox \
    "ruTorrent web UI username:" 8 40 "rutorrent" \
    --title "Username" 3>&1 1>&2 2>&3) || exit
  [[ -z "${RUTORRENT_USER}" ]] && RUTORRENT_USER="rutorrent"

  RUTORRENT_PASS=$(whiptail --passwordbox \
    "ruTorrent web UI password:\n\n(leave blank to generate a random password)" \
    10 55 "" --title "Password" 3>&1 1>&2 2>&3) || exit

  # Plugin checklist — clamp list height to terminal
  TERM_LINES=$(tput lines 2>/dev/null || echo 24)
  MAX_VISIBLE=$(( TERM_LINES - 8 ))
  [[ ${MAX_VISIBLE} -lt 5 ]] && MAX_VISIBLE=5
  [[ ${MAX_VISIBLE} -gt ${#PLUGIN_DEFS[@]} ]] && MAX_VISIBLE=${#PLUGIN_DEFS[@]}

  CHECKLIST_ITEMS=()
  for entry in "${PLUGIN_DEFS[@]}"; do
    IFS='|' read -r slug label default <<<"${entry}"
    CHECKLIST_ITEMS+=("${slug}" "${label}" "${default}")
  done

  SELECTED=$(whiptail --checklist "Select ruTorrent plugins to enable:" \
    $(( MAX_VISIBLE + 7 )) 72 "${MAX_VISIBLE}" \
    "${CHECKLIST_ITEMS[@]}" \
    --title "Plugin Selection" 3>&1 1>&2 2>&3) || exit

  RUTORRENT_PLUGINS=$(echo "${SELECTED}" | tr -d '"' | tr ' ' ',')

  # /RPC2 endpoint
  if whiptail --yesno \
    "Enable /RPC2 endpoint?\n\n(required for Sonarr, Radarr, autodl-irssi)" \
    10 55 --title "XMLRPC Endpoint" --defaultno 3>&1 1>&2 2>&3; then
    RUTORRENT_ENABLE_RPC2="yes"
  else
    RUTORRENT_ENABLE_RPC2="no"
  fi

  # Real IP (reverse proxy)
  if whiptail --yesno \
    "Enable real IP forwarding?\n\n(only needed if nginx is behind a reverse proxy\nsuch as Traefik, Cloudflare, or NPM)" \
    11 60 --title "Real IP" --defaultno 3>&1 1>&2 2>&3; then
    RUTORRENT_ENABLE_REAL_IP="yes"
  else
    RUTORRENT_ENABLE_REAL_IP="no"
  fi

  # Upload size limit
  RUTORRENT_MAX_UPLOAD_MB=$(whiptail --inputbox \
    "Maximum upload file size in MiB:\n\n(applied to filedrop, PHP, and nginx)" \
    10 55 "32" --title "Upload Limit" 3>&1 1>&2 2>&3) || exit
  [[ -z "${RUTORRENT_MAX_UPLOAD_MB}" ]] && RUTORRENT_MAX_UPLOAD_MB=32

  # Service user
  RUTORRENT_SERVICE_USER=$(whiptail --inputbox \
    "rTorrent system service username:\n\n(a dedicated user is created with this name)" \
    9 52 "torrent" --title "Service User" 3>&1 1>&2 2>&3) || exit
  [[ -z "${RUTORRENT_SERVICE_USER}" ]] && RUTORRENT_SERVICE_USER="torrent"

fi

# Apply defaults for non-interactive / pre-seeded runs
RUTORRENT_USER="${RUTORRENT_USER:-rutorrent}"
RUTORRENT_PASS="${RUTORRENT_PASS:-}"
RUTORRENT_ENABLE_RPC2="${RUTORRENT_ENABLE_RPC2:-no}"
RUTORRENT_ENABLE_REAL_IP="${RUTORRENT_ENABLE_REAL_IP:-no}"
RUTORRENT_MAX_UPLOAD_MB="${RUTORRENT_MAX_UPLOAD_MB:-32}"
RUTORRENT_SERVICE_USER="${RUTORRENT_SERVICE_USER:-torrent}"
[[ "${RUTORRENT_SERVICE_USER}" == "root" ]] && RUTORRENT_SERVICE_USER="torrent"

export RUTORRENT_USER RUTORRENT_PASS RUTORRENT_PLUGINS RUTORRENT_ENABLE_RPC2 RUTORRENT_ENABLE_REAL_IP RUTORRENT_MAX_UPLOAD_MB RUTORRENT_SERVICE_USER

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/www/rutorrent ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "rutorrent" "Novik/ruTorrent"; then
    msg_info "Backing up ruTorrent configuration"
    cp /var/www/rutorrent/conf/config.php /tmp/rutorrent-config.php 2>/dev/null || true
    cp /var/www/rutorrent/conf/plugins.ini /tmp/rutorrent-plugins.ini 2>/dev/null || true
    msg_ok "Backed up ruTorrent configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rutorrent" "Novik/ruTorrent" "tarball" "latest" "/var/www/rutorrent"

    msg_info "Restoring ruTorrent configuration"
    [[ -f /tmp/rutorrent-config.php ]] && cp /tmp/rutorrent-config.php /var/www/rutorrent/conf/config.php
    [[ -f /tmp/rutorrent-plugins.ini ]] && cp /tmp/rutorrent-plugins.ini /var/www/rutorrent/conf/plugins.ini
    rm -f /tmp/rutorrent-config.php /tmp/rutorrent-plugins.ini
    chown -R www-data:www-data /var/www/rutorrent
    msg_ok "Restored ruTorrent configuration"

    msg_ok "Updated ${APP} successfully"
  fi

  cleanup_lxc
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/${CL}"
echo -e "${INFO}${YW} Web UI credentials are in ${BGN}~/rutorrent.creds${CL} inside the container.${CL}"
