#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/tools.func)

set -eEo pipefail

color
formatting
icons
set_std_mode

SILENT_LOGFILE="/tmp/arr-stack-$$.log"
silent() { "$@" >>"$SILENT_LOGFILE" 2>&1; }

msg_info()  { echo -e "${INFO:-[i]} ${YW}${1}${CL}"; }
msg_ok()    { echo -e "${CM:-[ok]} ${GN}${1}${CL}"; }
msg_warn()  { echo -e "${YW}[WARN]${CL} ${1}"; }
msg_error() { echo -e "${CROSS:-[x]} ${RD}${1}${CL}"; }
msg_step()  { echo -e "${BL}==>${CL} ${1}"; }

cancelled() { msg_warn "Cancelled at $1."; exit 0; }

var_container_storage="${var_container_storage:-}"
var_template_storage="${var_template_storage:-}"
var_bridge="${var_bridge:-}"
var_gateway="${var_gateway:-}"
var_cidr="${var_cidr:-24}"
var_start_ctid="${var_start_ctid:-}"
var_repo="${var_repo:-ProxmoxVE}"
var_qbt_password="${var_qbt_password:-}"
SUMMARY_FILE="${SUMMARY_FILE:-/root/arr-stack-summary.txt}"

QBT_PERMANENT=0

BACKTITLE="Proxmox VE Helper Scripts — arr Stack"

TEMP_DIR=$(mktemp -d)
_on_exit() {
  local rc=$?
  if (( rc != 0 )); then
    if (( ${#INSTALLED_SLUGS[@]} > 0 )); then orphan_report; fi
    if [[ -s "$SILENT_LOGFILE" ]]; then
      echo
      msg_error "Last 20 lines of ${SILENT_LOGFILE}:"
      tail -n 20 "$SILENT_LOGFILE"
    fi
  fi
  rm -rf "$TEMP_DIR"
}
trap _on_exit EXIT

declare -A APP

SELECTED_ARRS=""
SELECTED_CLIENTS=""
ORDERED_SLUGS=()
INSTALLED_SLUGS=()
WIRING_RESULTS=()
WIRING_FAILURES=()

SYNC_CATEGORIES_SONARR='[5000,5010,5020,5030,5040,5045,5050]'
SYNC_CATEGORIES_RADARR='[2000,2010,2020,2030,2040,2045,2050,2060]'
SYNC_CATEGORIES_LIDARR='[3000,3010,3020,3030,3040]'

header_info() {
  clear
  cat <<"EOF"
                              _             _
   __ _ _ __ _ __         ___| |_ __ _  ___| | __
  / _` | '__| '__| ____  / __| __/ _` |/ __| |/ /
 | (_| | |  | |   |____| \__ \ || (_| | (__|   <
  \__,_|_|  |_|          |___/\__\__,_|\___|_|\_\

EOF
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    msg_error "Run this script as root."
    exit 1
  fi
}

check_pve_tools() {
  local missing=()
  for cmd in pct pvesh pvesm; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} > 0 )); then
    msg_error "Missing Proxmox VE tools: ${missing[*]}. Run this on a PVE node."
    exit 1
  fi
}

wait_for_port() {
  local ip=$1 port=$2 timeout=${3:-60} elapsed=0
  while ! (echo > "/dev/tcp/${ip}/${port}") >/dev/null 2>&1; do
    sleep 2
    elapsed=$((elapsed + 2))
    if (( elapsed >= timeout )); then return 1; fi
  done
  return 0
}

is_valid_ipv4() {
  local ip=$1
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  local a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]} c=${BASH_REMATCH[3]} d=${BASH_REMATCH[4]}
  (( a <= 255 && b <= 255 && c <= 255 && d <= 255 )) || return 1
  return 0
}

form_input_program() {
  if command -v dialog >/dev/null 2>&1; then
    echo "dialog"
  elif whiptail --help 2>&1 | grep -q -- '--form'; then
    echo "whiptail"
  else
    echo "none"
  fi
}

seed_catalog() {
  while IFS='|' read -r slug script port impl apiver kind name contract; do
    [[ -z "$slug" ]] && continue
    APP[$slug.script]="$script"
    APP[$slug.port]="$port"
    APP[$slug.impl]="$impl"
    APP[$slug.apiver]="$apiver"
    APP[$slug.kind]="$kind"
    APP[$slug.name]="$name"
    APP[$slug.contract]="$contract"
  done <<'EOF'
prowlarr|prowlarr.sh|9696||v1|indexer|Prowlarr|
sonarr|sonarr.sh|8989|Sonarr|v3|arr|Sonarr|SonarrSettings
radarr|radarr.sh|7878|Radarr|v3|arr|Radarr|RadarrSettings
lidarr|lidarr.sh|8686|Lidarr|v1|arr|Lidarr|LidarrSettings
seerr|seerr.sh|5055||-|requests|Seerr|
qbittorrent|qbittorrent.sh|8090|QBittorrent|-|client|qBittorrent|QBittorrentSettings
sabnzbd|sabnzbd.sh|7777|Sabnzbd|-|client|SABnzbd|SabnzbdSettings
EOF
}

pick_storage() {
  if [[ -n "$var_container_storage" ]]; then
    msg_info "Container storage (from env): ${var_container_storage}"
  else
    local options=() row name type
    while IFS= read -r row; do
      name=$(awk '{print $1}' <<<"$row")
      type=$(awk '{print $2}' <<<"$row")
      [[ -z "$name" ]] && continue
      options+=("$name" "$type")
    done < <(pvesm status -content rootdir 2>/dev/null | awk 'NR>1')

    if (( ${#options[@]} == 0 )); then
      msg_error "No PVE storage with content 'rootdir' available."
      exit 1
    fi

    if (( ${#options[@]} == 2 )); then
      var_container_storage="${options[0]}"
      msg_info "Container storage (only option): ${var_container_storage}"
    else
      var_container_storage=$(whiptail --backtitle "$BACKTITLE" \
        --title "Container Storage" \
        --menu "Pick a PVE storage for the container rootfs:" 20 70 10 \
        "${options[@]}" 3>&1 1>&2 2>&3) || cancelled "storage pick"
    fi
  fi

  if [[ -z "$var_template_storage" ]]; then
    var_template_storage=$(pvesm status -content vztmpl 2>/dev/null \
      | awk 'NR>1 && $1=="local" {print $1; exit}')
    [[ -z "$var_template_storage" ]] && var_template_storage=$(pvesm status -content vztmpl 2>/dev/null \
      | awk 'NR>1 {print $1; exit}')
  fi
  [[ -n "$var_template_storage" ]] && msg_info "Template storage: ${var_template_storage}"
}

pick_network_defaults() {
  if [[ -z "$var_bridge" ]]; then
    local options=() b
    while IFS= read -r b; do
      [[ -n "$b" ]] && options+=("$b" "")
    done < <(awk '/^iface vmbr/ {print $2}' /etc/network/interfaces 2>/dev/null)

    if (( ${#options[@]} == 0 )); then
      options=("vmbr0" "")
    fi

    var_bridge=$(whiptail --backtitle "$BACKTITLE" \
      --title "Network Bridge" \
      --menu "Pick the Linux bridge for all containers:" 15 60 6 \
      "${options[@]}" 3>&1 1>&2 2>&3) || cancelled "bridge pick"
  fi

  local default_gw
  default_gw=$(ip -4 route show default | awk '{print $3}' | head -n1)

  while [[ -z "$var_gateway" ]] || ! is_valid_ipv4 "$var_gateway"; do
    var_gateway=$(whiptail --backtitle "$BACKTITLE" \
      --title "Gateway" \
      --inputbox "IPv4 gateway for the container subnet (leave blank for default: $default_gw):" 10 70 \
      "${var_gateway:-$default_gw}" 3>&1 1>&2 2>&3) || cancelled "gateway prompt"

    if [[ -z "$var_gateway" && -n "$default_gw" ]]; then
      var_gateway="$default_gw"
    fi

    if ! is_valid_ipv4 "$var_gateway"; then
      whiptail --backtitle "$BACKTITLE" --title "Invalid" \
        --msgbox "Not a valid IPv4 address: ${var_gateway}" 8 60
      var_gateway=""
    fi
  done

  while true; do
    var_cidr=$(whiptail --backtitle "$BACKTITLE" \
      --title "CIDR Mask" \
      --inputbox "Network mask (1-32, e.g. 24):" 10 60 \
      "${var_cidr:-24}" 3>&1 1>&2 2>&3) || cancelled "CIDR prompt"
    if [[ "$var_cidr" =~ ^[0-9]+$ ]] && (( var_cidr >= 1 && var_cidr <= 32 )); then
      break
    fi
    whiptail --backtitle "$BACKTITLE" --title "Invalid" \
      --msgbox "CIDR must be an integer between 1 and 32." 8 60
  done

  msg_info "Bridge ${var_bridge} | gateway ${var_gateway} | mask /${var_cidr}"
}

pick_apps() {
  while true; do
    local choice
    choice=$(whiptail --backtitle "$BACKTITLE" \
      --title "Pick *arr Apps" \
      --checklist "Prowlarr is always installed. Pick additional apps:" 16 70 6 \
      "sonarr" "Sonarr (TV)" ON \
      "radarr" "Radarr (Movies)" ON \
      "lidarr" "Lidarr (Music)" OFF \
      "seerr"  "Seerr (Requests)" OFF \
      3>&1 1>&2 2>&3) || cancelled "*arr app pick"

    SELECTED_ARRS=$(echo "$choice" | tr -d '"')

    if [[ -z "$SELECTED_ARRS" ]]; then
      if whiptail --backtitle "$BACKTITLE" --title "Confirm" \
        --yesno "You picked no *arr apps. Only Prowlarr will be installed and there will be nothing to wire. Continue anyway?" 10 70; then
        return
      fi
      continue
    fi
    return
  done
}

pick_clients() {
  local choice
  choice=$(whiptail --backtitle "$BACKTITLE" \
    --title "Pick Download Clients" \
    --checklist "Optional download clients to install + wire:" 14 70 4 \
    "qbittorrent" "qBittorrent (Torrents)" ON \
    "sabnzbd"     "SABnzbd (Usenet)" OFF \
    3>&1 1>&2 2>&3) || cancelled "download client pick"

  SELECTED_CLIENTS=$(echo "$choice" | tr -d '"')
}

_gen_password() {
  local p
  p=$(openssl rand -base64 18 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-16)
  [[ -z "$p" ]] && p="ChangeMe${RANDOM}${RANDOM}"
  printf '%s' "$p"
}

pick_qbittorrent_password() {
  [[ " $SELECTED_CLIENTS " == *" qbittorrent "* ]] || return
  [[ -n "$var_qbt_password" ]] && { msg_info "qBittorrent password (from env) will be used."; return; }

  local choice
  choice=$(whiptail --backtitle "$BACKTITLE" \
    --title "qBittorrent WebUI Password" \
    --menu "Set the qBittorrent admin password:" 15 70 2 \
    "generate" "Auto-generate a strong random password (recommended)" \
    "manual"   "Enter my own password" \
    3>&1 1>&2 2>&3) || cancelled "qBittorrent password pick"

  if [[ "$choice" == "generate" ]]; then
    var_qbt_password=$(_gen_password)
    msg_info "A random qBittorrent password was generated (shown in the final summary)."
    return
  fi

  local pw1 pw2
  while true; do
    pw1=$(whiptail --backtitle "$BACKTITLE" --title "qBittorrent Password" \
      --passwordbox "Enter a WebUI password (min 6 chars):" 10 60 \
      3>&1 1>&2 2>&3) || cancelled "qBittorrent password entry"
    pw2=$(whiptail --backtitle "$BACKTITLE" --title "Confirm Password" \
      --passwordbox "Re-enter the password:" 10 60 \
      3>&1 1>&2 2>&3) || cancelled "qBittorrent password confirm"

    if [[ "$pw1" != "$pw2" ]]; then
      whiptail --backtitle "$BACKTITLE" --title "Mismatch" \
        --msgbox "Passwords do not match. Try again." 8 50
      continue
    fi
    if (( ${#pw1} < 6 )); then
      whiptail --backtitle "$BACKTITLE" --title "Too short" \
        --msgbox "Password must be at least 6 characters." 8 50
      continue
    fi
    var_qbt_password="$pw1"
    return
  done
}

compute_ordered_slugs() {
  ORDERED_SLUGS=("prowlarr")
  local s
  for s in $SELECTED_ARRS; do
    [[ "$s" == "seerr" ]] && continue
    ORDERED_SLUGS+=("$s")
  done
  for s in $SELECTED_CLIENTS; do
    ORDERED_SLUGS+=("$s")
  done
  for s in $SELECTED_ARRS; do
    [[ "$s" == "seerr" ]] && ORDERED_SLUGS+=("seerr")
  done
}

pick_ip_mode_and_ips() {
  while true; do
    local mode
    mode=$(whiptail --backtitle "$BACKTITLE" \
      --title "IP Entry Mode" \
      --menu "How would you like to enter IP addresses?" 15 75 2 \
      "list" "Enter all IPs at once (space- or comma-separated)" \
      "form" "Enter each IP in a form" \
      3>&1 1>&2 2>&3) || cancelled "IP entry mode pick"

    case "$mode" in
      list) _collect_ips_list_mode; return ;;
      form)
        if _collect_ips_one_by_one; then
          return
        fi
        ;;
    esac
  done
}

_collect_ips_list_mode() {
  local expected_n=${#ORDERED_SLUGS[@]}
  local hint="" s
  for s in "${ORDERED_SLUGS[@]}"; do hint+="  ${s}"$'\n'; done

  while true; do
    local raw
    raw=$(whiptail --backtitle "$BACKTITLE" \
      --title "Enter ${expected_n} IPv4 addresses" \
      --inputbox "Enter ${expected_n} IPs separated by spaces or commas, in this order:"$'\n\n'"${hint}" \
      22 78 "" 3>&1 1>&2 2>&3) || cancelled "IP list entry"

    local normalized="${raw//,/ }"
    local -a ips=()
    # shellcheck disable=SC2206
    ips=( $normalized )

    if (( ${#ips[@]} != expected_n )); then
      whiptail --backtitle "$BACKTITLE" --title "Wrong count" \
        --msgbox "Expected ${expected_n} IPs, got ${#ips[@]}. Please re-enter." 8 60
      continue
    fi

    local ok=1 i
    for i in "${!ips[@]}"; do
      if ! is_valid_ipv4 "${ips[$i]}"; then
        whiptail --backtitle "$BACKTITLE" --title "Invalid" \
          --msgbox "Entry $((i+1)) is not a valid IPv4: ${ips[$i]}" 8 60
        ok=0; break
      fi
      if [[ "${ips[$i]}" == "$var_gateway" ]]; then
        whiptail --backtitle "$BACKTITLE" --title "Invalid" \
          --msgbox "Entry $((i+1)) collides with the gateway: ${ips[$i]}" 8 60
        ok=0; break
      fi
    done
    (( ok == 0 )) && continue

    local dup
    dup=$(printf '%s\n' "${ips[@]}" | sort | uniq -d | head -n1)
    if [[ -n "$dup" ]]; then
      whiptail --backtitle "$BACKTITLE" --title "Duplicate IP" \
        --msgbox "IP appears more than once: ${dup}" 8 60
      continue
    fi

    for i in "${!ORDERED_SLUGS[@]}"; do
      APP[${ORDERED_SLUGS[$i]}.ip]=${ips[$i]}
    done
    return
  done
}

_collect_ips_one_by_one() {
  local ui
  ui=$(form_input_program)

  if [[ "$ui" == "dialog" ]]; then
    local expected_n=${#ORDERED_SLUGS[@]}
    local -a form_fields=()
    local slug

    for slug in "${ORDERED_SLUGS[@]}"; do
      form_fields+=("$slug" "")
    done

    while true; do
      local raw_values
      if ! raw_values=$(dialog --backtitle "$BACKTITLE" \
        --title "Container IP Addresses" \
        --form "Enter an IPv4 address for each container:" 22 78 0 \
        "${form_fields[@]}" 2>&1 >/dev/tty); then
        msg_warn "IP form entry cancelled."
        return 1
      fi

      local -a ips=()
      mapfile -t ips <<< "$raw_values"

      if (( ${#ips[@]} != expected_n )); then
        whiptail --backtitle "$BACKTITLE" --title "Wrong count" \
          --msgbox "Expected ${expected_n} IPs, got ${#ips[@]}. Please re-enter." 8 60
        continue
      fi

      local ok=1 i
      for i in "${!ips[@]}"; do
        local ip="${ips[$i]}"
        if ! is_valid_ipv4 "$ip"; then
          whiptail --backtitle "$BACKTITLE" --title "Invalid" \
            --msgbox "Entry $((i+1)) is not a valid IPv4: ${ip}" 8 60
          ok=0
          break
        fi
        if [[ "$ip" == "$var_gateway" ]]; then
          whiptail --backtitle "$BACKTITLE" --title "Invalid" \
            --msgbox "Entry $((i+1)) collides with the gateway: ${ip}" 8 60
          ok=0
          break
        fi
        if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
          whiptail --backtitle "$BACKTITLE" --title "IP In Use" \
            --msgbox "Entry $((i+1)) is already in use by another device: ${ip}" 8 60
          ok=0
          break
        fi
      done
      (( ok == 0 )) && continue

      local dup
      dup=$(printf '%s\n' "${ips[@]}" | sort | uniq -d | head -n1)
      if [[ -n "$dup" ]]; then
        whiptail --backtitle "$BACKTITLE" --title "Duplicate IP" \
          --msgbox "IP appears more than once: ${dup}" 8 60
        continue
      fi

      for i in "${!ORDERED_SLUGS[@]}"; do
        APP[${ORDERED_SLUGS[$i]}.ip]=${ips[$i]}
      done
      return 0
    done
  fi

  if [[ "$ui" == "whiptail" ]]; then
    local expected_n=${#ORDERED_SLUGS[@]}
    local -a form_fields=()
    local slug

    for slug in "${ORDERED_SLUGS[@]}"; do
      form_fields+=("$slug" "")
    done

    while true; do
      local raw_values
      if ! raw_values=$(whiptail --backtitle "$BACKTITLE" \
        --title "Container IP Addresses" \
        --separate-output \
        --form "Enter an IPv4 address for each container:" 22 78 "$((expected_n + 4))" \
        "${form_fields[@]}" 3>&1 1>&2 2>&3); then
        msg_warn "IP form entry cancelled."
        return 1
      fi

      local -a ips=()
      mapfile -t ips <<< "$raw_values"

      if (( ${#ips[@]} != expected_n )); then
        whiptail --backtitle "$BACKTITLE" --title "Wrong count" \
          --msgbox "Expected ${expected_n} IPs, got ${#ips[@]}. Please re-enter." 8 60
        continue
      fi

      local ok=1 i
      for i in "${!ips[@]}"; do
        local ip="${ips[$i]}"
        if ! is_valid_ipv4 "$ip"; then
          whiptail --backtitle "$BACKTITLE" --title "Invalid" \
            --msgbox "Entry $((i+1)) is not a valid IPv4: ${ip}" 8 60
          ok=0
          break
        fi
        if [[ "$ip" == "$var_gateway" ]]; then
          whiptail --backtitle "$BACKTITLE" --title "Invalid" \
            --msgbox "Entry $((i+1)) collides with the gateway: ${ip}" 8 60
          ok=0
          break
        fi
        if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
          whiptail --backtitle "$BACKTITLE" --title "IP In Use" \
            --msgbox "Entry $((i+1)) is already in use by another device: ${ip}" 8 60
          ok=0
          break
        fi
      done
      (( ok == 0 )) && continue

      local dup
      dup=$(printf '%s\n' "${ips[@]}" | sort | uniq -d | head -n1)
      if [[ -n "$dup" ]]; then
        whiptail --backtitle "$BACKTITLE" --title "Duplicate IP" \
          --msgbox "IP appears more than once: ${dup}" 8 60
        continue
      fi

      for i in "${!ORDERED_SLUGS[@]}"; do
        APP[${ORDERED_SLUGS[$i]}.ip]=${ips[$i]}
      done
      return 0
    done
  fi

  local slug ip running="" last_ip="" default_ip=""
  for slug in "${ORDERED_SLUGS[@]}"; do
    if [[ -n "$last_ip" ]]; then
      local prefix="${last_ip%.*}"
      local host="${last_ip##*.}"
      if [[ "$host" =~ ^[0-9]+$ ]] && (( host < 254 )); then
        default_ip="${prefix}.$((host + 1))"
      fi
    fi
    while true; do
      local prompt="Enter IPv4 for ${slug}:"
      [[ -n "$running" ]] && prompt+=$'\n\nAlready assigned:'"$running"
      ip=$(whiptail --backtitle "$BACKTITLE" \
        --title "Container IP Addresses" \
        --inputbox "$prompt" 16 60 "$default_ip" 3>&1 1>&2 2>&3) || { msg_warn "IP entry cancelled."; return 1; }

      if ! is_valid_ipv4 "$ip"; then
        whiptail --backtitle "$BACKTITLE" --title "Invalid" \
          --msgbox "Not a valid IPv4: ${ip}" 8 60
        continue
      fi
      if [[ "$ip" == "$var_gateway" ]]; then
        whiptail --backtitle "$BACKTITLE" --title "Invalid" \
          --msgbox "Collides with the gateway: ${ip}" 8 60
        continue
      fi

      local dup=0 other_slug other_ip
      for other_slug in "${ORDERED_SLUGS[@]}"; do
        [[ "$other_slug" == "$slug" ]] && continue
        other_ip="${APP[${other_slug}.ip]:-}"
        [[ -n "$other_ip" && "$other_ip" == "$ip" ]] && { dup=1; break; }
      done
      if (( dup )); then
        whiptail --backtitle "$BACKTITLE" --title "Duplicate" \
          --msgbox "Already used by another container: ${ip}" 8 60
        continue
      fi

      APP[$slug.ip]=$ip
      running+=$'\n  '"${slug} -> ${ip}"
      last_ip=$ip
      break
    done
  done

  return 0
}

pick_start_ctid() {
  local default_start
  if [[ -n "$var_start_ctid" ]]; then
    default_start="$var_start_ctid"
  else
    default_start=$(pvesh get /cluster/nextid 2>/dev/null || echo "100")
  fi

  local start
  start=$(whiptail --backtitle "$BACKTITLE" \
    --title "Starting CTID" \
    --inputbox "Starting Container ID (in-use IDs are skipped):" 10 60 \
    "$default_start" 3>&1 1>&2 2>&3) || cancelled "starting CTID prompt"

  if ! [[ "$start" =~ ^[0-9]+$ ]]; then
    msg_error "Invalid CTID: $start"
    exit 1
  fi

  local id=$start s
  for s in "${ORDERED_SLUGS[@]}"; do
    while pct status "$id" >/dev/null 2>&1; do
      id=$((id + 1))
      (( id > 999999 )) && { msg_error "Ran out of CTID space."; exit 1; }
    done
    APP[$s.ctid]=$id
    id=$((id + 1))
  done
}

confirm_summary() {
  local lines="" s
  for s in "${ORDERED_SLUGS[@]}"; do
    lines+="  $(printf '%-12s ctid=%-5s ip=%-16s port=%s' \
      "$s" "${APP[$s.ctid]}" "${APP[$s.ip]}" "${APP[$s.port]}")"$'\n'
  done

  local body="About to create these containers and wire them together:"$'\n\n'"${lines}"$'\n'"Storage: ${var_container_storage} | Bridge: ${var_bridge} | Gateway: ${var_gateway} | Mask: /${var_cidr}"

  whiptail --backtitle "$BACKTITLE" --title "Confirm" \
    --yesno "$body" 22 78 || { msg_warn "User cancelled."; exit 0; }
}

orphan_report() {
  if (( ${#INSTALLED_SLUGS[@]} == 0 )); then return; fi
  msg_error "Containers already created (to clean up, run):"
  local s
  for s in "${INSTALLED_SLUGS[@]}"; do
    echo "  pct stop ${APP[$s.ctid]} && pct destroy ${APP[$s.ctid]}   # ${s}"
  done
}

install_loop() {
  local total=${#ORDERED_SLUGS[@]} idx=0
  local s script_file ip ctid port

  exec 4> >(whiptail --backtitle "$BACKTITLE" --title "Installing Containers" --gauge "Starting installation..." 10 70 0)

  for s in "${ORDERED_SLUGS[@]}"; do
    idx=$((idx + 1))
    ip="${APP[$s.ip]}"
    ctid="${APP[$s.ctid]}"
    port="${APP[$s.port]}"
    script_file="$TEMP_DIR/${s}.sh"

    local base_pct=$(( (idx - 1) * 100 / total ))
    local half_pct=$(( base_pct + (50 / total) ))
    local full_pct=$(( idx * 100 / total ))

    echo -e "XXX\n${base_pct}\n[${idx}/${total}] Downloading ct/${s}.sh...\nXXX" >&4

    $STD curl -fsSL \
      "https://raw.githubusercontent.com/community-scripts/${var_repo}/main/ct/${s}.sh" \
      -o "$script_file"

    if [[ ! -s "$script_file" ]]; then
      exec 4>&-
      msg_error "Empty/failed download for ${s}"
      exit 1
    fi

    echo -e "XXX\n${half_pct}\n[${idx}/${total}] Installing ${s} -> ctid=${ctid} ip=${ip}/${var_cidr}\nXXX" >&4

    $STD env \
      MODE=generated mode=generated PHS_SILENT=1 \
      var_ctid="$ctid" \
      var_hostname="$s" \
      var_brg="$var_bridge" \
      var_net="${ip}/${var_cidr}" \
      var_gateway="$var_gateway" \
      var_container_storage="$var_container_storage" \
      var_template_storage="$var_template_storage" \
      bash "$script_file"

    INSTALLED_SLUGS+=("$s")

    if [[ "${APP[$s.kind]}" == "arr" || "${APP[$s.kind]}" == "indexer" ]]; then
      echo -e "XXX\n${half_pct}\n[${idx}/${total}] Waiting for ${s} to listen on ${port}...\nXXX" >&4
      if ! wait_for_port "$ip" "$port" 90; then
        # Handled silently; warning is re-issued during extraction
        :
      fi
    fi

    echo -e "XXX\n${full_pct}\n[${idx}/${total}] Installed ${s}\nXXX" >&4
  done

  exec 4>&-
  sleep 0.1

  for s in "${ORDERED_SLUGS[@]}"; do
    msg_ok "Installed ${s}"
  done
}

extract_arr_key() {
  local slug=$1 ctid=$2 ip=$3 port=$4
  local config_dir="/var/lib/${slug}/config.xml"

  msg_info "Waiting for ${slug} on ${ip}:${port}..."
  wait_for_port "$ip" "$port" 240 || { msg_error "${slug} never opened ${port}"; return 1; }

  local i
  for ((i=0; i<60; i++)); do
    if pct exec "$ctid" -- test -f "$config_dir" 2>/dev/null; then break; fi
    sleep 2
  done

  local key
  key=$(pct exec "$ctid" -- sed -n 's:.*<ApiKey>\([^<]*\)</ApiKey>.*:\1:p' "$config_dir" 2>/dev/null | head -n1 || true)
  if [[ -z "$key" ]]; then
    msg_error "Failed to extract API key for ${slug} (config: ${config_dir})"
    return 1
  fi
  APP[$slug.apikey]="$key"
  msg_ok "${slug} apikey extracted (${key:0:6}…)"
}

extract_qbittorrent_password() {
  local ctid=$1 ip=$2
  APP[qbittorrent.user]="admin"

  msg_info "Waiting for qbittorrent on ${ip}:8090..."
  if ! wait_for_port "$ip" 8090 240; then
    msg_warn "qbittorrent never opened 8090; assuming legacy default admin/adminadmin."
    APP[qbittorrent.pass]="adminadmin"
    return 1
  fi

  # The community-script installs qBittorrent with a hardcoded adminadmin password.
  # We skip searching for a temporary password to prevent a 60s hang,
  # since we will overwrite the password with the user's custom one anyway.
  APP[qbittorrent.pass]="adminadmin"
}

qbt_password_hash() {
  # qBittorrent WebUI password format: @ByteArray(<b64 salt>:<b64 key>)
  # PBKDF2-HMAC-SHA512, 100000 iterations, 16-byte salt, 64-byte derived key.
  # Pure Perl (Digest::SHA + MIME::Base64 are core modules, always present on PVE).
  local plain=$1
  PW="$plain" perl -e '
    use strict; use warnings;
    use Digest::SHA qw(hmac_sha512);
    use MIME::Base64 qw(encode_base64);
    my $pw = $ENV{PW};
    open(my $r, "<", "/dev/urandom") or die "urandom: $!";
    my $salt; read($r, $salt, 16) == 16 or die "salt read"; close($r);
    my $iter = 100000;
    # dkLen (64) == hLen (64), so only block T_1 is needed.
    my $u = hmac_sha512($salt . pack("N", 1), $pw);
    my $t = $u;
    for (2 .. $iter) { $u = hmac_sha512($u, $pw); $t ^= $u; }
    print "\@ByteArray(" . encode_base64($salt, "") . ":" . encode_base64($t, "") . ")";
  ' 2>/dev/null
}

set_qbittorrent_permanent_password() {
  local ctid=$1 plain=$2
  local conf hashval localconf edited meta uid gid perms pushed=1

  conf=$(pct exec "$ctid" -- bash -c 'find /root /home /opt /var/lib -name qBittorrent.conf 2>/dev/null | head -n1' 2>/dev/null || true)
  if [[ -z "$conf" ]]; then
    msg_warn "qBittorrent.conf not found in ctid ${ctid}; keeping temporary password."
    return 1
  fi

  hashval=$(qbt_password_hash "$plain")
  if [[ -z "$hashval" ]]; then
    msg_warn "Could not compute qBittorrent password hash; keeping temporary password."
    return 1
  fi

  localconf="$TEMP_DIR/qBittorrent.conf"
  if ! pct pull "$ctid" "$conf" "$localconf" >/dev/null 2>&1; then
    msg_warn "Could not read ${conf} from ctid ${ctid}; keeping temporary password."
    return 1
  fi

  meta=$(pct exec "$ctid" -- stat -c '%u %g %a' "$conf" 2>/dev/null || true)
  read -r uid gid perms <<<"$meta"

  # qbittorrent-nox rewrites its conf on shutdown, so stop it before editing.
  pct exec "$ctid" -- systemctl stop qbittorrent-nox >/dev/null 2>&1 || true

  # Insert/replace WebUI\Password_PBKDF2 under [Preferences], preserving the rest.
  # Done in Perl so the literal backslash in the key is unambiguous.
  edited="$TEMP_DIR/qBittorrent.conf.new"
  if ! QBT_HASH="$hashval" QBT_SRC="$localconf" QBT_DST="$edited" perl -e '
    use strict; use warnings;
    my $key  = q{WebUI\Password_PBKDF2};
    my $hash = $ENV{QBT_HASH};
    open(my $in, "<", $ENV{QBT_SRC}) or die "read: $!";
    my @lines = <$in>; close($in);
    my @out; my $inprefs = 0; my $done = 0;
    for my $ln (@lines) {
      if ($ln =~ /^\[/) {
        if ($inprefs && !$done) { push @out, qq{$key="$hash"\n}; $done = 1; }
        $inprefs = ($ln =~ /^\[Preferences\]\s*$/) ? 1 : 0;
      }
      if ($inprefs && index($ln, "$key=") == 0) {
        if (!$done) { push @out, qq{$key="$hash"\n}; $done = 1; }
        next;
      }
      push @out, $ln;
    }
    unless ($done) {
      push @out, "[Preferences]\n" unless $inprefs;
      push @out, qq{$key="$hash"\n};
    }
    open(my $o, ">", $ENV{QBT_DST}) or die "write: $!";
    print $o @out; close($o);
  '; then
    msg_warn "Failed to edit qBittorrent.conf; restarting service with temporary password."
    pct exec "$ctid" -- systemctl start qbittorrent-nox >/dev/null 2>&1 || true
    return 1
  fi

  if [[ -n "$uid" && -n "$gid" && -n "$perms" ]]; then
    pct push "$ctid" "$edited" "$conf" --user "$uid" --group "$gid" --perms "$perms" >/dev/null 2>&1 || pushed=0
  else
    pct push "$ctid" "$edited" "$conf" >/dev/null 2>&1 || pushed=0
  fi

  pct exec "$ctid" -- systemctl start qbittorrent-nox >/dev/null 2>&1 || true

  if (( pushed == 0 )); then
    msg_warn "Could not write updated qBittorrent.conf to ctid ${ctid}; keeping temporary password."
    return 1
  fi

  PASS_BY_SLUG[qbittorrent]="$plain"
  APP[qbittorrent.pass]="$plain"
  QBT_PERMANENT=1
  msg_ok "qBittorrent permanent WebUI password set."
}

extract_sabnzbd_key() {
  local ctid=$1 ip=$2

  msg_info "Waiting for sabnzbd on ${ip}:7777..."
  wait_for_port "$ip" 7777 240 || { msg_warn "sabnzbd never opened 7777"; return 1; }

  local ini="" candidate
  for candidate in /opt/sabnzbd/sabnzbd.ini /root/.sabnzbd/sabnzbd.ini /etc/sabnzbd/sabnzbd.ini; do
    if pct exec "$ctid" -- test -f "$candidate" 2>/dev/null; then
      ini="$candidate"; break
    fi
  done
  if [[ -z "$ini" ]]; then
    msg_warn "Could not locate sabnzbd.ini inside ctid ${ctid}; SABnzbd will need manual setup."
    return 1
  fi

  local key="" i
  for ((i=0; i<60; i++)); do
    key=$(pct exec "$ctid" -- awk -F' *= *' '/^api_key/ {print $2; exit}' "$ini" 2>/dev/null || true)
    [[ -n "$key" ]] && break
    sleep 2
  done

  if [[ -z "$key" ]]; then
    msg_warn "sabnzbd api_key not yet written. Open the web wizard once at http://${ip}:7777 and rerun wiring."
    return 1
  fi
  APP[sabnzbd.apikey]="$key"
  msg_ok "sabnzbd apikey extracted (${key:0:6}…)"
}

wait_and_extract_keys() {
  msg_step "Extracting credentials & API keys"
  local s ctid ip port
  for s in "${ORDERED_SLUGS[@]}"; do
    ctid="${APP[$s.ctid]}"
    ip="${APP[$s.ip]}"
    port="${APP[$s.port]}"
    case "${APP[$s.kind]}" in
      indexer|arr)
        extract_arr_key "$s" "$ctid" "$ip" "$port" || true
        ;;
      client)
        if [[ "$s" == "qbittorrent" ]]; then
          extract_qbittorrent_password "$ctid" "$ip" || true
          [[ -z "$var_qbt_password" ]] && var_qbt_password=$(_gen_password)
          set_qbittorrent_permanent_password "$ctid" "$var_qbt_password" || true
        elif [[ "$s" == "sabnzbd" ]]; then
          extract_sabnzbd_key "$ctid" "$ip" || true
        fi
        ;;
      requests)
        msg_warn "Seerr requires the web first-run wizard. URL + keys will be in the summary."
        ;;
    esac
  done
}

record_wiring()  { WIRING_RESULTS+=("$1"); }
record_failure() { WIRING_FAILURES+=("$1"); }

api_post() {
  local url=$1 apikey=$2 payload=$3 label=$4
  local resp status=""
  resp=$(curl -fsS --max-time 30 --retry 2 \
    -H "X-Api-Key: $apikey" \
    -H "Content-Type: application/json" \
    -X POST "$url" -d "$payload" \
    -w '\n__HTTP__%{http_code}' 2>&1) || status="curl_fail"

  local code=""
  if [[ "$resp" =~ __HTTP__([0-9]+)$ ]]; then
    code="${BASH_REMATCH[1]}"
  fi

  if [[ "$status" == "curl_fail" || -z "$code" || "$code" -ge 400 ]]; then
    record_failure "${label}  FAIL (http ${code:-?})"
    msg_warn "${label} failed (http ${code:-?})"
    return 1
  fi
  record_wiring "${label}  OK"
  msg_ok "${label}"
}

probe_lidarr_api_version() {
  if [[ -z "${APP[lidarr.apikey]:-}" ]]; then return; fi
  local ip="${APP[lidarr.ip]}" key="${APP[lidarr.apikey]}"
  if curl -fsS --max-time 10 -H "X-Api-Key: $key" \
       "http://${ip}:8686/api/v3/system/status" >/dev/null 2>&1; then
    APP[lidarr.apiver]="v3"
    msg_info "Lidarr supports /api/v3 — using v3 for wiring."
  fi
}

wire_arrs_into_prowlarr() {
  local prowlarr_ip="${APP[prowlarr.ip]}"
  local prowlarr_key="${APP[prowlarr.apikey]:-}"
  if [[ -z "$prowlarr_key" ]]; then
    msg_warn "Skipping Prowlarr wiring — no Prowlarr API key."
    return
  fi

  local s sync_cats payload
  for s in $SELECTED_ARRS; do
    [[ "$s" == "seerr" ]] && continue
    local key="${APP[$s.apikey]:-}"
    if [[ -z "$key" ]]; then
      record_failure "Prowlarr -> ${APP[$s.name]}  FAIL (no apikey)"
      continue
    fi

    case "$s" in
      sonarr) sync_cats="$SYNC_CATEGORIES_SONARR" ;;
      radarr) sync_cats="$SYNC_CATEGORIES_RADARR" ;;
      lidarr) sync_cats="$SYNC_CATEGORIES_LIDARR" ;;
      *)      sync_cats='[]' ;;
    esac

    payload=$(jq -n \
      --arg name "${APP[$s.name]}" \
      --arg impl "${APP[$s.impl]}" \
      --arg contract "${APP[$s.contract]}" \
      --arg prowlarr_url "http://${prowlarr_ip}:9696" \
      --arg base_url "http://${APP[$s.ip]}:${APP[$s.port]}" \
      --arg apikey "$key" \
      --argjson sync_cats "$sync_cats" \
      '{
        name: $name,
        syncLevel: "fullSync",
        implementation: $impl,
        implementationName: $impl,
        configContract: $contract,
        tags: [],
        fields: [
          { name: "prowlarrUrl",    value: $prowlarr_url },
          { name: "baseUrl",        value: $base_url },
          { name: "apiKey",         value: $apikey },
          { name: "syncCategories", value: $sync_cats }
        ]
      }')

    api_post "http://${prowlarr_ip}:9696/api/v1/applications" \
      "$prowlarr_key" "$payload" \
      "Prowlarr -> ${APP[$s.name]}" || true
  done
}

wire_clients_into_arrs() {
  local arr client arr_key arr_ip arr_port api_ver category_field category_name payload url sab_key

  for arr in $SELECTED_ARRS; do
    [[ "$arr" == "seerr" ]] && continue
    arr_key="${APP[$arr.apikey]:-}"
    if [[ -z "$arr_key" ]]; then
      msg_warn "Skipping download-client wiring for ${arr} — no API key."
      continue
    fi
    arr_ip="${APP[$arr.ip]}"
    arr_port="${APP[$arr.port]}"
    api_ver="${APP[$arr.apiver]}"

    case "$arr" in
      sonarr) category_field="tvCategory";    category_name="tv-sonarr" ;;
      radarr) category_field="movieCategory"; category_name="radarr"    ;;
      lidarr) category_field="musicCategory"; category_name="lidarr"    ;;
    esac

    for client in $SELECTED_CLIENTS; do
      url="http://${arr_ip}:${arr_port}/api/${api_ver}/downloadclient?forceSave=true"

      if [[ "$client" == "qbittorrent" ]]; then
        payload=$(jq -n \
          --arg host "${APP[qbittorrent.ip]}" \
          --argjson port 8090 \
          --arg user "${APP[qbittorrent.user]}" \
          --arg pass "${APP[qbittorrent.pass]}" \
          --arg category_field "$category_field" \
          --arg category_name "$category_name" \
          '{
            enable: true, protocol: "torrent", priority: 1,
            name: "qBittorrent",
            implementation: "QBittorrent",
            implementationName: "qBittorrent",
            configContract: "QBittorrentSettings",
            tags: [],
            fields: [
              { name: "host",     value: $host },
              { name: "port",     value: $port },
              { name: "useSsl",   value: false },
              { name: "username", value: $user },
              { name: "password", value: $pass },
              { name: $category_field, value: $category_name }
            ]
          }')
        api_post "$url" "$arr_key" "$payload" \
          "${APP[$arr.name]} -> qBittorrent" || true

      elif [[ "$client" == "sabnzbd" ]]; then
        sab_key="${APP[sabnzbd.apikey]:-}"
        if [[ -z "$sab_key" ]]; then
          record_failure "${APP[$arr.name]} -> SABnzbd  FAIL (no sab apikey)"
          continue
        fi
        payload=$(jq -n \
          --arg host "${APP[sabnzbd.ip]}" \
          --argjson port 7777 \
          --arg apikey "$sab_key" \
          --arg category_field "$category_field" \
          --arg category_name "$category_name" \
          '{
            enable: true, protocol: "usenet", priority: 1,
            name: "SABnzbd",
            implementation: "Sabnzbd",
            implementationName: "SABnzbd",
            configContract: "SabnzbdSettings",
            tags: [],
            fields: [
              { name: "host",   value: $host },
              { name: "port",   value: $port },
              { name: "apiKey", value: $apikey },
              { name: "useSsl", value: false },
              { name: $category_field, value: $category_name }
            ]
          }')
        api_post "$url" "$arr_key" "$payload" \
          "${APP[$arr.name]} -> SABnzbd" || true
      fi
    done
  done
}

wire_apis() {
  msg_step "Wiring apps together via HTTP APIs"
  probe_lidarr_api_version
  wire_arrs_into_prowlarr
  wire_clients_into_arrs

  if [[ " $SELECTED_ARRS " == *" seerr "* ]]; then
    record_wiring "Seerr -> (manual via web wizard)"
    msg_warn "Seerr can't be wired headlessly. URLs and keys are in the summary."
  fi
}

write_summary() {
  msg_step "Writing summary"
  local now host
  now=$(date '+%Y-%m-%d %H:%M:%S %Z')
  host=$(hostname)
  local lines=()
  lines+=( "\e[1;36m============================================================\e[0m" )
  lines+=( "" )
  lines+=( "\e[1;33m[Shared settings]\e[0m" )
  lines+=( "  Bridge:     ${var_bridge}" )
  lines+=( "  Gateway:    ${var_gateway}" )
  lines+=( "  CIDR:       /${var_cidr}" )
  lines+=( "  CT storage: ${var_container_storage}" )
  lines+=( "  Template:   ${var_template_storage}" )
  lines+=( "" )

  lines+=( "\e[1;33m[Containers]\e[0m" )
  local s
  for s in "${ORDERED_SLUGS[@]}"; do
    lines+=( "$(printf '  \e[1m%-12s\e[0m ctid=%-5s ip=%-16s \e[4murl=http://%s:%s\e[0m' \
      "$s" "${APP[$s.ctid]}" "${APP[$s.ip]}" "${APP[$s.ip]}" "${APP[$s.port]}")" )
  done
  lines+=( "" )

  lines+=( "\e[1;33m[Credentials & API keys]\e[0m" )
  for s in "${ORDERED_SLUGS[@]}"; do
    case "${APP[$s.kind]}" in
      indexer|arr)
        if [[ -n "${APP[$s.apikey]:-}" ]]; then
          lines+=( "$(printf '  %-12s apikey: \e[32m%s\e[0m' "$s" "${APP[$s.apikey]}")" )
        else
          lines+=( "$(printf '  %-12s apikey: \e[31m(not extracted)\e[0m' "$s")" )
        fi
        ;;
      client)
        if [[ "$s" == "qbittorrent" ]]; then
          lines+=( "$(printf '  %-12s user:   \e[32m%s\e[0m' "$s" "${APP[qbittorrent.user]:-admin}")" )
        elif [[ "$s" == "sabnzbd" ]]; then
          if [[ -n "${APP[sabnzbd.apikey]:-}" ]]; then
            lines+=( "$(printf '  %-12s apikey: \e[32m%s\e[0m' "$s" "${APP[sabnzbd.apikey]}")" )
          else
            lines+=( "$(printf '  %-12s apikey: \e[33m(open web wizard at http://%s:7777 once)\e[0m' "$s" "${APP[sabnzbd.ip]}")" )
          fi
        fi
        ;;
      requests)
        lines+=( "$(printf '  %-12s \e[33m(set during first-run web wizard)\e[0m' "$s")" )
        ;;
    esac
  done
  lines+=( "" )

  lines+=( "\e[1;33m[Wired automatically]\e[0m" )
  if (( ${#WIRING_RESULTS[@]} == 0 )); then
    lines+=( "  (nothing)" )
  else
    local w
    for w in "${WIRING_RESULTS[@]}"; do lines+=( "  \e[32m✔ ${w}\e[0m" ); done
  fi
  lines+=( "" )

  if (( ${#WIRING_FAILURES[@]} > 0 )); then
    lines+=( "\e[1;31m[Wiring failures]\e[0m" )
    local f
    for f in "${WIRING_FAILURES[@]}"; do lines+=( "  \e[31m✖ ${f}\e[0m" ); done
    lines+=( "" )
  fi

  lines+=( "\e[1;41;37m !!! MANUAL STEPS STILL REQUIRED !!! \e[0m" )
  lines+=( "\e[1;31m------------------------------------------------------------\e[0m" )
  lines+=( "  - \e[1mProwlarr:\e[0m Add indexers (none ship by default)." )
  lines+=( "  - \e[1mSonarr/Radarr/Lidarr:\e[0m Set root folders and at least one quality profile." )
  if [[ " $SELECTED_CLIENTS " == *" sabnzbd "* ]]; then
    lines+=( "  - \e[1mSABnzbd:\e[0m Open \e[4mhttp://${APP[sabnzbd.ip]}:7777\e[0m and complete the web wizard." )
  fi
  if [[ " $SELECTED_ARRS " == *" seerr "* ]]; then
    lines+=( "  - \e[1mSeerr:\e[0m Open \e[4mhttp://${APP[seerr.ip]}:5055\e[0m, complete the wizard, then add:" )
    for s in $SELECTED_ARRS; do
      [[ "$s" == "seerr" ]] || [[ "$s" == "lidarr" ]] && continue
      lines+=( "       -> \e[1m${APP[$s.name]}\e[0m at \e[4mhttp://${APP[$s.ip]}:${APP[$s.port]}\e[0m  (API Key: \e[32m${APP[$s.apikey]:-<missing>}\e[0m)" )
    done
  fi
  lines+=( "\e[1;31m------------------------------------------------------------\e[0m" )
  lines+=( "" )
  lines+=( "Summary written to \e[36m${SUMMARY_FILE}\e[0m (chmod 600)." )
  lines+=( "\e[1;36m============================================================\e[0m" )

  local body
  body=$(printf '%s\n' "${lines[@]}")

  echo
  echo -e "$body"

  # Write raw summary without colors
  ( umask 077; echo -e "$body" | sed 's/\x1b\[[0-9;]*m//g' > "$SUMMARY_FILE" )
  chmod 600 "$SUMMARY_FILE" 2>/dev/null || true

  msg_ok "Wrote ${SUMMARY_FILE}"
}

main() {
  header_info
  check_root
  check_pve_tools
  ensure_dependencies curl whiptail jq iputils-ping
  seed_catalog
  pick_storage
  pick_network_defaults
  pick_apps
  pick_clients
  pick_qbittorrent_password
  compute_ordered_slugs
  pick_ip_mode_and_ips
  pick_start_ctid
  confirm_summary
  install_loop
  wait_and_extract_keys
  wire_apis
  write_summary
  msg_ok "arr-stack provisioning finished."
}

main "$@"
