#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Trawis
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
load_functions

function header_info() {
  clear
  cat <<"EOF"
                 _____                          _
  _ __ _   _   |_   _|__  _ __ _ __ ___ _ __ | |_
 | '__| | | |    | |/ _ \| '__| '__/ _ \ '_ \| __|
 | |  | |_| |    | | (_) | |  | | |  __/ | | | |_
 |_|   \__,_|    |_|\___/|_|  |_|  \___|_| |_|\__|
                  Reconfigure
EOF
}

if [[ ! -d /var/www/rutorrent ]]; then
  msg_error "No ruTorrent installation found. Run this script inside the ruTorrent container."
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  msg_error "Run as root."
  exit 1
fi

NGINX_CONF=/etc/nginx/sites-available/rutorrent
HTPASSWD=/etc/nginx/.rutorrent_htpasswd
PLUGINS_INI=/var/www/rutorrent/conf/plugins.ini
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.4")
PHP_UPLOAD_INI=/etc/php/${PHP_VER}/fpm/conf.d/99-rutorrent-upload.ini
FILEDROP_CONF=/var/www/rutorrent/plugins/filedrop/conf.php

detect_upload_limit() {
  grep -oP 'client_max_body_size \K[0-9]+' "$NGINX_CONF" 2>/dev/null || echo "32"
}

detect_rpc2() {
  grep -q 'location /RPC2' "$NGINX_CONF" 2>/dev/null && echo "yes" || echo "no"
}

detect_real_ip() {
  grep -q 'set_real_ip_from' "$NGINX_CONF" 2>/dev/null && echo "yes" || echo "no"
}

write_nginx_conf() {
  local upload_mb="$1" enable_rpc2="$2" enable_real_ip="$3"
  local rpc2_block="" real_ip_block=""

  if [[ "$enable_rpc2" == "yes" ]]; then
    rpc2_block="
    location /RPC2 {
        include scgi_params;
        scgi_pass unix:///run/rtorrent/rtorrent.sock;
    }
"
  fi

  if [[ "$enable_real_ip" == "yes" ]]; then
    real_ip_block="
    set_real_ip_from 127.0.0.1;
    set_real_ip_from 10.0.0.0/8;
    set_real_ip_from 172.16.0.0/12;
    set_real_ip_from 192.168.0.0/16;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;
"
  fi

  cat <<EOF >"$NGINX_CONF"
server {
    listen 80;
    server_name _;

    root /var/www/rutorrent;
    index index.html index.php;

    client_max_body_size ${upload_mb}M;

    auth_basic "ruTorrent";
    auth_basic_user_file /etc/nginx/.rutorrent_htpasswd;
${real_ip_block}${rpc2_block}
    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/rutorrent-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

  if ! nginx -t &>/dev/null; then
    msg_error "nginx config test failed — reverting"
    return 1
  fi
}

action_change_password() {
  header_info
  local users username newpass

  users=$(awk -F: '{print $1}' "$HTPASSWD" 2>/dev/null | tr '\n' '  ')

  username=$(whiptail --inputbox \
    "Username to update (or new username to add):\n\nExisting: ${users}" \
    10 60 "" --title "Change Password" 3>&1 1>&2 2>&3) || return
  [[ -z "$username" ]] && return

  newpass=$(whiptail --passwordbox \
    "New password for '${username}':\n\n(leave blank to generate random)" \
    10 55 "" --title "Change Password" 3>&1 1>&2 2>&3) || return

  [[ -z "$newpass" ]] && newpass=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)

  htpasswd -b "$HTPASSWD" "$username" "$newpass" &>/dev/null
  systemctl reload nginx

  local creds_user
  creds_user=$(grep "^Username:" ~/rutorrent.creds 2>/dev/null | awk '{print $2}')
  if [[ "$username" == "$creds_user" ]]; then
    sed -i "s/^Password:.*/Password: ${newpass}/" ~/rutorrent.creds 2>/dev/null || true
  fi

  msg_ok "Password updated for '${username}'"
  echo -e " ${INFO} ${YW}New password: ${newpass}${CL}"
  echo ""
  read -rp "Press Enter to continue..."
}

action_toggle_rpc2() {
  header_info
  local current rpc2_new
  current=$(detect_rpc2)

  if [[ "$current" == "yes" ]]; then
    whiptail --yesno "/RPC2 is currently ENABLED.\n\nDisable it?" \
      9 55 --title "Toggle /RPC2" 3>&1 1>&2 2>&3 || return
    rpc2_new="no"
  else
    whiptail --yesno "/RPC2 is currently DISABLED.\n\nEnable it?\n(required for Sonarr, Radarr, autodl-irssi)" \
      10 58 --title "Toggle /RPC2" 3>&1 1>&2 2>&3 || return
    rpc2_new="yes"
  fi

  write_nginx_conf "$(detect_upload_limit)" "$rpc2_new" "$(detect_real_ip)" || {
    read -rp "Press Enter to continue..."
    return
  }
  systemctl reload nginx
  msg_ok "/RPC2 endpoint $([ "$rpc2_new" = "yes" ] && echo "enabled" || echo "disabled")"
  echo ""
  read -rp "Press Enter to continue..."
}

action_toggle_real_ip() {
  header_info
  local current real_ip_new
  current=$(detect_real_ip)

  if [[ "$current" == "yes" ]]; then
    whiptail --yesno "Real IP forwarding is currently ENABLED.\n\nDisable it?" \
      9 58 --title "Toggle Real IP" 3>&1 1>&2 2>&3 || return
    real_ip_new="no"
  else
    whiptail --yesno "Real IP forwarding is currently DISABLED.\n\nEnable it?\n(only for reverse proxy setups: Traefik, Cloudflare, NPM)" \
      11 62 --title "Toggle Real IP" 3>&1 1>&2 2>&3 || return
    real_ip_new="yes"
  fi

  write_nginx_conf "$(detect_upload_limit)" "$(detect_rpc2)" "$real_ip_new" || {
    read -rp "Press Enter to continue..."
    return
  }
  systemctl reload nginx
  msg_ok "Real IP forwarding $([ "$real_ip_new" = "yes" ] && echo "enabled" || echo "disabled")"
  echo ""
  read -rp "Press Enter to continue..."
}

action_change_upload_limit() {
  header_info
  local current_mb new_mb

  current_mb=$(detect_upload_limit)

  new_mb=$(whiptail --inputbox \
    "Maximum upload file size in MiB:\n(applied to nginx, PHP, and filedrop plugin)" \
    10 58 "$current_mb" --title "Upload Limit" 3>&1 1>&2 2>&3) || return
  [[ -z "$new_mb" ]] && return

  if ! [[ "$new_mb" =~ ^[0-9]+$ ]] || [[ "$new_mb" -lt 1 ]]; then
    msg_error "Invalid value — must be a positive integer"
    read -rp "Press Enter to continue..."
    return
  fi

  write_nginx_conf "$new_mb" "$(detect_rpc2)" "$(detect_real_ip)" || {
    read -rp "Press Enter to continue..."
    return
  }

  cat <<EOF >"$PHP_UPLOAD_INI"
upload_max_filesize = ${new_mb}M
post_max_size = ${new_mb}M
EOF

  if [[ -f "$FILEDROP_CONF" ]]; then
    local upload_bytes filedrop_pat
    upload_bytes=$(( new_mb * 1024 * 1024 ))
    filedrop_pat='\(\$maxFileSize\s*=\s*\)'
    sed -i "s/${filedrop_pat}[0-9]*/\1${upload_bytes}/" "$FILEDROP_CONF"
  fi

  systemctl reload nginx
  systemctl restart "php${PHP_VER}-fpm"
  msg_ok "Upload limit set to ${new_mb} MiB"
  echo ""
  read -rp "Press Enter to continue..."
}

action_manage_plugins() {
  header_info

  if [[ ! -f "$PLUGINS_INI" ]]; then
    msg_error "plugins.ini not found at $PLUGINS_INI"
    read -rp "Press Enter to continue..."
    return
  fi

  local -a slugs states
  local current_slug=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
      current_slug="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^enabled[[:space:]]*=[[:space:]]*(yes|no) ]] && [[ -n "$current_slug" ]]; then
      slugs+=("$current_slug")
      states+=("${BASH_REMATCH[1]}")
      current_slug=""
    fi
  done <"$PLUGINS_INI"

  if [[ ${#slugs[@]} -eq 0 ]]; then
    msg_error "No plugins found in $PLUGINS_INI"
    read -rp "Press Enter to continue..."
    return
  fi

  local checklist_items=()
  for i in "${!slugs[@]}"; do
    local state="OFF"
    [[ "${states[$i]}" == "yes" ]] && state="ON"
    checklist_items+=("${slugs[$i]}" "${slugs[$i]}" "$state")
  done

  local TERM_LINES max_visible
  TERM_LINES=$(tput lines 2>/dev/null || echo 24)
  max_visible=$(( TERM_LINES - 8 ))
  [[ $max_visible -lt 5 ]] && max_visible=5
  [[ $max_visible -gt ${#slugs[@]} ]] && max_visible=${#slugs[@]}

  local selected
  selected=$(whiptail --checklist "Enable/disable plugins (Space to toggle):" \
    $(( max_visible + 7 )) 62 "$max_visible" \
    "${checklist_items[@]}" \
    --title "Plugin Manager" 3>&1 1>&2 2>&3) || return

  local -A enabled_set=()
  local sel_slug
  for sel_slug in $(echo "$selected" | tr -d '"'); do
    enabled_set["$sel_slug"]=1
  done

  : >"$PLUGINS_INI"
  for slug in "${slugs[@]}"; do
    if [[ "${enabled_set[$slug]+_}" ]]; then
      printf '[%s]\nenabled = yes\n\n' "$slug" >>"$PLUGINS_INI"
    else
      printf '[%s]\nenabled = no\n\n' "$slug" >>"$PLUGINS_INI"
    fi
  done
  chown www-data:www-data "$PLUGINS_INI"

  msg_ok "plugins.ini updated — reload the ruTorrent browser tab to apply"
  echo ""
  read -rp "Press Enter to continue..."
}

action_show_status() {
  header_info
  local rpc2 real_ip upload_mb
  rpc2=$(detect_rpc2)
  real_ip=$(detect_real_ip)
  upload_mb=$(detect_upload_limit)

  echo -e "${BL}--- Configuration ---${CL}"
  echo -e "  Upload limit:     ${YW}${upload_mb} MiB${CL}"
  echo -e "  /RPC2 endpoint:   ${YW}${rpc2}${CL}"
  echo -e "  Real IP forward:  ${YW}${real_ip}${CL}"
  echo -e "  PHP version:      ${YW}${PHP_VER}${CL}"
  echo -e "  ruTorrent:        ${YW}$(cat /var/www/rutorrent/version.txt 2>/dev/null || echo unknown)${CL}"
  echo ""
  echo -e "${BL}--- Services ---${CL}"
  for svc in rtorrent nginx "php${PHP_VER}-fpm"; do
    if systemctl is-active --quiet "$svc"; then
      echo -e "  ${svc}: ${GN}active${CL}"
    else
      echo -e "  ${svc}: ${RD}inactive${CL}"
    fi
  done
  echo ""
  echo -e "${BL}--- Credentials ---${CL}"
  if [[ -f ~/rutorrent.creds ]]; then
    cat ~/rutorrent.creds
  else
    echo -e "  ${YW}~/rutorrent.creds not found${CL}"
  fi
  echo ""
  read -rp "Press Enter to continue..."
}

# --- Main ---

header_info

while true; do
  RPC2=$(detect_rpc2)
  REAL_IP=$(detect_real_ip)
  UPLOAD=$(detect_upload_limit)

  CHOICE=$(whiptail --title "ruTorrent Reconfigure" \
    --menu "upload=${UPLOAD}MiB  rpc2=${RPC2}  real-ip=${REAL_IP}" \
    17 65 7 \
    "1" "Change web UI password" \
    "2" "Toggle /RPC2 endpoint         [${RPC2}]" \
    "3" "Toggle real IP forwarding      [${REAL_IP}]" \
    "4" "Change upload size limit       [${UPLOAD} MiB]" \
    "5" "Manage plugins" \
    "6" "Show status" \
    "0" "Exit" \
    3>&1 1>&2 2>&3) || break

  case "$CHOICE" in
    1) action_change_password ;;
    2) action_toggle_rpc2 ;;
    3) action_toggle_real_ip ;;
    4) action_change_upload_limit ;;
    5) action_manage_plugins ;;
    6) action_show_status ;;
    0) break ;;
  esac

  header_info
done

msg_ok "Done."
