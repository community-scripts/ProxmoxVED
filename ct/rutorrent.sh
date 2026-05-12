#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trawis
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Novik/ruTorrent

APP="ruTorrent"
var_tags="${var_tags:-torrent;bittorrent;rtorrent}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-0}"
var_fuse="${var_fuse:-no}"
var_tun="${var_tun:-no}"
var_gpu="${var_gpu:-no}"
var_keyctl="${var_keyctl:-0}"
var_mknod="${var_mknod:-0}"
var_protection="${var_protection:-no}"
var_ssh="${var_ssh:-no}"

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
  "erasedata|Erase Data|on"
  "extratio|Extra Ratio|on"
  "extsearch|External Search|on"
  "feeds|Feeds|on"
  "filedrop|File Drop|on"
  "geoip|GeoIP|on"
  "history|History|on"
  "httprpc|HTTP RPC|on"
  "ipad|iPad|on"
  "loginmgr|Login Manager|on"
  "lookat|Look At|on"
  "mediainfo|Media Info|on"
  "ratiocolor|Ratio Color|on"
  "rpc|RPC|on"
  "rssurlrewrite|RSS URL Rewrite|on"
  "scheduler|Scheduler|on"
  "screenshots|Screenshots|on"
  "seedingtime|Seeding Time|on"
  "show_peers_like_wtorrent|Show Peers Like wTorrent|on"
  "source|Source|on"
  "spectrogram|Spectrogram (needs sox)|off"
  "theme|Theme|on"
  "trafic|Traffic|on"
  "unpack|Unpack|on"
  "xmpp|XMPP (broken: PHP 8 incompatible)|off"
  "_cloudflare|Cloudflare|on"
  "dump|Dump (dumptorrent not in Debian 13 repos)|off"
  "throttle|Throttle (broken: old rTorrent API)|off"
  "retrackers|Retrackers|on"
  "rutracker_check|RuTracker Check|on"
  "uploadeta|Upload ETA|on"
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

  # Upload size limit
  RUTORRENT_MAX_UPLOAD_MB=$(whiptail --inputbox \
    "Maximum upload file size in MiB:\n\n(applied to filedrop, PHP, and nginx)" \
    10 55 "32" --title "Upload Limit" 3>&1 1>&2 2>&3) || exit
  [[ -z "${RUTORRENT_MAX_UPLOAD_MB}" ]] && RUTORRENT_MAX_UPLOAD_MB=32

fi

# Apply defaults for non-interactive / pre-seeded runs
RUTORRENT_USER="${RUTORRENT_USER:-rutorrent}"
RUTORRENT_PASS="${RUTORRENT_PASS:-}"
RUTORRENT_ENABLE_RPC2="${RUTORRENT_ENABLE_RPC2:-no}"
RUTORRENT_MAX_UPLOAD_MB="${RUTORRENT_MAX_UPLOAD_MB:-32}"

# Strip plugins that require a privileged container when running unprivileged.
# Add slug names to PRIVILEGED_ONLY_PLUGINS as needed.
PRIVILEGED_ONLY_PLUGINS=()
if [[ "${var_unprivileged}" == "1" ]] && [[ ${#PRIVILEGED_ONLY_PLUGINS[@]} -gt 0 ]]; then
  for plugin in "${PRIVILEGED_ONLY_PLUGINS[@]}"; do
    if [[ ",${RUTORRENT_PLUGINS}," == *",${plugin},"* ]]; then
      msg_warn "Plugin '${plugin}' requires a privileged container — disabling."
      RUTORRENT_PLUGINS="${RUTORRENT_PLUGINS//${plugin}/}"
      RUTORRENT_PLUGINS="${RUTORRENT_PLUGINS//,,/,}"
      RUTORRENT_PLUGINS="${RUTORRENT_PLUGINS#,}"
      RUTORRENT_PLUGINS="${RUTORRENT_PLUGINS%,}"
    fi
  done
fi

export RUTORRENT_USER RUTORRENT_PASS RUTORRENT_PLUGINS RUTORRENT_ENABLE_RPC2 RUTORRENT_MAX_UPLOAD_MB

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/www/rutorrent ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for ruTorrent Update"
  CURRENT=$(cat /var/www/rutorrent/version.txt 2>/dev/null || echo "unknown")
  LATEST=$(curl -fsSL https://api.github.com/repos/Novik/ruTorrent/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)

  if [[ -z "${LATEST}" ]]; then
    msg_error "Unable to determine latest ruTorrent release."
    exit
  fi

  if [[ "${CURRENT}" == "${LATEST}" ]]; then
    msg_ok "ruTorrent is already up to date (${CURRENT})"
    exit
  fi

  msg_info "Updating ruTorrent ${CURRENT} → ${LATEST}"
  $STD git -C /var/www/rutorrent fetch --tags --force
  $STD git -C /var/www/rutorrent checkout "${LATEST}"
  echo "${LATEST}" >/var/www/rutorrent/version.txt
  chown -R www-data:www-data /var/www/rutorrent
  msg_ok "Updated ruTorrent to ${LATEST}"
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
