#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/core.func)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/tools.func)

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
var_repo="${var_repo:-ProxmoxVED}"
SUMMARY_FILE="${SUMMARY_FILE:-/root/arr-stack-summary.txt}"

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

declare -A CTID_BY_SLUG
declare -A IP_BY_SLUG
declare -A PORT_BY_SLUG
declare -A APIKEY_BY_SLUG
declare -A USER_BY_SLUG
declare -A PASS_BY_SLUG
declare -A SCRIPT_BY_SLUG
declare -A IMPL_BY_SLUG
declare -A KIND_BY_SLUG
declare -A ARR_API_VER_BY_SLUG
declare -A NAME_BY_SLUG
declare -A CONFIG_CONTRACT_BY_SLUG

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
   __ _ _ __ _ __       ___| |_ __ _  ___| | __
  / _` | '__| '__|____ / __| __/ _` |/ __| |/ /
 | (_| | |  | | |_____|\__ \ || (_| | (__|   <
  \__,_|_|  |_|       |___/\__\__,_|\___|_|\_\

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

seed_catalog() {
  while IFS='|' read -r slug script port impl apiver kind name contract; do
    [[ -z "$slug" ]] && continue
    SCRIPT_BY_SLUG[$slug]="$script"
    PORT_BY_SLUG[$slug]="$port"
    IMPL_BY_SLUG[$slug]="$impl"
    ARR_API_VER_BY_SLUG[$slug]="$apiver"
    KIND_BY_SLUG[$slug]="$kind"
    NAME_BY_SLUG[$slug]="$name"
    CONFIG_CONTRACT_BY_SLUG[$slug]="$contract"
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

  while [[ -z "$var_gateway" ]] || ! is_valid_ipv4 "$var_gateway"; do
    var_gateway=$(whiptail --backtitle "$BACKTITLE" \
      --title "Gateway" \
      --inputbox "IPv4 gateway for the container subnet:" 10 60 \
      "${var_gateway:-}" 3>&1 1>&2 2>&3) || cancelled "gateway prompt"
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
      --menu "How would you like to enter IP addresses?" 15 75 3 \
      "list"       "Enter all IPs at once (space- or comma-separated)" \
      "one_by_one" "Prompt per container" \
      "auto"       "Auto-pick free IPs from a starting IP or range(s)" \
      3>&1 1>&2 2>&3) || cancelled "IP entry mode pick"

    case "$mode" in
      list)       _collect_ips_list_mode; return ;;
      one_by_one) _collect_ips_one_by_one; return ;;
      auto)       _collect_ips_auto && return ;;
    esac
  done
}

_parse_ip_ranges() {
  local expr=$1
  local -a segments
  IFS=',' read -ra segments <<<"$expr"
  local seg prefix start end i
  for seg in "${segments[@]}"; do
    seg="${seg// /}"
    [[ -z "$seg" ]] && continue
    if [[ "$seg" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.)([0-9]+)-([0-9]+\.[0-9]+\.[0-9]+\.)([0-9]+)$ ]]; then
      if [[ "${BASH_REMATCH[1]}" != "${BASH_REMATCH[3]}" ]]; then
        echo "ERR: cross-subnet range not supported: $seg" >&2; return 1
      fi
      prefix=${BASH_REMATCH[1]}; start=${BASH_REMATCH[2]}; end=${BASH_REMATCH[4]}
    elif [[ "$seg" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.)([0-9]+)-([0-9]+)$ ]]; then
      prefix=${BASH_REMATCH[1]}; start=${BASH_REMATCH[2]}; end=${BASH_REMATCH[3]}
    elif [[ "$seg" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.)([0-9]+)$ ]]; then
      prefix=${BASH_REMATCH[1]}; start=${BASH_REMATCH[2]}; end=254
    else
      echo "ERR: invalid segment: $seg" >&2; return 1
    fi
    if (( start > end || start < 0 || end > 255 )); then
      echo "ERR: out-of-range octet: $seg" >&2; return 1
    fi
    for ((i=start; i<=end; i++)); do
      echo "${prefix}${i}"
    done
  done
}

_ip_is_free() {
  local ip=$1
  [[ "$ip" == "$var_gateway" ]] && return 1
  if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

_collect_ips_auto() {
  local expected_n=${#ORDERED_SLUGS[@]}
  local hint="Examples:"$'\n'"  10.0.0.50                       (start, scans upward to .254)"$'\n'"  10.0.0.50-99                    (single range)"$'\n'"  10.0.0.50-60,10.0.0.80-99       (multiple ranges)"

  while true; do
    local expr
    expr=$(whiptail --backtitle "$BACKTITLE" \
      --title "Auto IP allocation" \
      --inputbox "Need ${expected_n} free IPs. Enter a starting IP or range expression:"$'\n\n'"${hint}" \
      16 78 "" 3>&1 1>&2 2>&3) || return 1

    local -a parsed=()
    while IFS= read -r ip; do
      [[ -n "$ip" ]] && parsed+=("$ip")
    done < <(_parse_ip_ranges "$expr" 2>/dev/null)

    if (( ${#parsed[@]} == 0 )); then
      whiptail --backtitle "$BACKTITLE" --title "Invalid" \
        --msgbox "Could not parse any IPs from: ${expr}"$'\n\n'"Try a starting IP, a range like 10.0.0.50-99, or comma-separated ranges." 12 70
      continue
    fi

    msg_info "Pinging ${#parsed[@]} candidate(s) for ${expected_n} free IP(s)..."
    local -a found=()
    local ip already used
    for ip in "${parsed[@]}"; do
      (( ${#found[@]} >= expected_n )) && break
      already=0
      for used in "${IP_BY_SLUG[@]}"; do
        [[ "$used" == "$ip" ]] && { already=1; break; }
      done
      (( already )) && continue
      if _ip_is_free "$ip"; then
        found+=("$ip")
        echo "  free: ${ip}"
      fi
    done

    if (( ${#found[@]} < expected_n )); then
      whiptail --backtitle "$BACKTITLE" --title "Not enough free IPs" \
        --msgbox "Found ${#found[@]}/${expected_n} free IPs in the range. Widen the range and try again." 10 70
      continue
    fi

    local lines="" i
    for i in "${!ORDERED_SLUGS[@]}"; do
      lines+="  $(printf '%-12s -> %s' "${ORDERED_SLUGS[$i]}" "${found[$i]}")"$'\n'
    done
    if ! whiptail --backtitle "$BACKTITLE" --title "Confirm auto-assigned IPs" \
         --yesno "Free IPs found:"$'\n\n'"${lines}"$'\n'"Use these?" 22 70; then
      continue
    fi

    for i in "${!ORDERED_SLUGS[@]}"; do
      IP_BY_SLUG[${ORDERED_SLUGS[$i]}]=${found[$i]}
    done
    return 0
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
      IP_BY_SLUG[${ORDERED_SLUGS[$i]}]=${ips[$i]}
    done
    return
  done
}

_collect_ips_one_by_one() {
  local slug ip running=""
  for slug in "${ORDERED_SLUGS[@]}"; do
    while true; do
      ip=$(whiptail --backtitle "$BACKTITLE" \
        --title "IP for ${slug}" \
        --inputbox "Enter IPv4 for ${slug}.${running:+$'\n\nAlready assigned:'}${running}" \
        16 60 "" 3>&1 1>&2 2>&3) || cancelled "IP prompt for ${slug}"

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
      local dup=0 other
      for other in "${IP_BY_SLUG[@]}"; do
        [[ "$other" == "$ip" ]] && { dup=1; break; }
      done
      if (( dup )); then
        whiptail --backtitle "$BACKTITLE" --title "Duplicate" \
          --msgbox "Already used by another container: ${ip}" 8 60
        continue
      fi

      IP_BY_SLUG[$slug]=$ip
      running+=$'\n  '"${slug} -> ${ip}"
      break
    done
  done
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
    CTID_BY_SLUG[$s]=$id
    id=$((id + 1))
  done
}

confirm_summary() {
  local lines="" s
  for s in "${ORDERED_SLUGS[@]}"; do
    lines+="  $(printf '%-12s ctid=%-5s ip=%-16s port=%s' \
      "$s" "${CTID_BY_SLUG[$s]}" "${IP_BY_SLUG[$s]}" "${PORT_BY_SLUG[$s]}")"$'\n'
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
    echo "  pct stop ${CTID_BY_SLUG[$s]} && pct destroy ${CTID_BY_SLUG[$s]}   # ${s}"
  done
}

install_loop() {
  local total=${#ORDERED_SLUGS[@]} idx=0
  local s script_file ip ctid port

  for s in "${ORDERED_SLUGS[@]}"; do
    idx=$((idx + 1))
    ip="${IP_BY_SLUG[$s]}"
    ctid="${CTID_BY_SLUG[$s]}"
    port="${PORT_BY_SLUG[$s]}"
    script_file="$TEMP_DIR/${s}.sh"

    msg_step "[${idx}/${total}] Downloading ct/${s}.sh"
    $STD curl -fsSL \
      "https://raw.githubusercontent.com/community-scripts/${var_repo}/main/ct/${s}.sh" \
      -o "$script_file"

    if [[ ! -s "$script_file" ]]; then
      msg_error "Empty/failed download for ${s}"
      exit 1
    fi

    msg_step "[${idx}/${total}] Installing ${s} -> ctid=${ctid} ip=${ip}/${var_cidr}"
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
    msg_ok "Installed ${s}"

    if [[ "${KIND_BY_SLUG[$s]}" == "arr" || "${KIND_BY_SLUG[$s]}" == "indexer" ]]; then
      msg_info "Waiting for ${s} to listen on ${port}..."
      if ! wait_for_port "$ip" "$port" 90; then
        msg_warn "${s} did not open ${port} within 90s; will retry during key extraction."
      fi
    fi
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
  APIKEY_BY_SLUG[$slug]="$key"
  msg_ok "${slug} apikey extracted (${key:0:6}…)"
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
  APIKEY_BY_SLUG[sabnzbd]="$key"
  msg_ok "sabnzbd apikey extracted (${key:0:6}…)"
}

wait_and_extract_keys() {
  msg_step "Extracting credentials & API keys"
  local s ctid ip port tmp
  for s in "${ORDERED_SLUGS[@]}"; do
    ctid="${CTID_BY_SLUG[$s]}"
    ip="${IP_BY_SLUG[$s]}"
    port="${PORT_BY_SLUG[$s]}"
    case "${KIND_BY_SLUG[$s]}" in
      indexer|arr)
        extract_arr_key "$s" "$ctid" "$ip" "$port" || true
        ;;
      client)
        if [[ "$s" == "qbittorrent" ]]; then
          USER_BY_SLUG[qbittorrent]="admin"
          PASS_BY_SLUG[qbittorrent]="adminadmin"
          tmp=$(pct exec "$ctid" -- bash -c "journalctl -u qbittorrent-nox --no-pager 2>/dev/null | grep -i 'temporary password' | tail -n1" 2>/dev/null || true)
          if [[ -n "$tmp" ]]; then
            msg_warn "qBittorrent journalctl mentioned a temporary password — see summary."
            PASS_BY_SLUG[qbittorrent]="<see journal: $tmp>"
          fi
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
  if [[ -z "${APIKEY_BY_SLUG[lidarr]:-}" ]]; then return; fi
  local ip="${IP_BY_SLUG[lidarr]}" key="${APIKEY_BY_SLUG[lidarr]}"
  if curl -fsS --max-time 10 -H "X-Api-Key: $key" \
       "http://${ip}:8686/api/v3/system/status" >/dev/null 2>&1; then
    ARR_API_VER_BY_SLUG[lidarr]="v3"
    msg_info "Lidarr supports /api/v3 — using v3 for wiring."
  fi
}

wire_arrs_into_prowlarr() {
  local prowlarr_ip="${IP_BY_SLUG[prowlarr]}"
  local prowlarr_key="${APIKEY_BY_SLUG[prowlarr]:-}"
  if [[ -z "$prowlarr_key" ]]; then
    msg_warn "Skipping Prowlarr wiring — no Prowlarr API key."
    return
  fi

  local s sync_cats payload
  for s in $SELECTED_ARRS; do
    [[ "$s" == "seerr" ]] && continue
    local key="${APIKEY_BY_SLUG[$s]:-}"
    if [[ -z "$key" ]]; then
      record_failure "Prowlarr -> ${NAME_BY_SLUG[$s]}  FAIL (no apikey)"
      continue
    fi

    case "$s" in
      sonarr) sync_cats="$SYNC_CATEGORIES_SONARR" ;;
      radarr) sync_cats="$SYNC_CATEGORIES_RADARR" ;;
      lidarr) sync_cats="$SYNC_CATEGORIES_LIDARR" ;;
      *)      sync_cats='[]' ;;
    esac

    payload=$(jq -n \
      --arg name "${NAME_BY_SLUG[$s]}" \
      --arg impl "${IMPL_BY_SLUG[$s]}" \
      --arg contract "${CONFIG_CONTRACT_BY_SLUG[$s]}" \
      --arg prowlarr_url "http://${prowlarr_ip}:9696" \
      --arg base_url "http://${IP_BY_SLUG[$s]}:${PORT_BY_SLUG[$s]}" \
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
      "Prowlarr -> ${NAME_BY_SLUG[$s]}" || true
  done
}

wire_clients_into_arrs() {
  local arr client arr_key arr_ip arr_port api_ver category_field category_name payload url sab_key

  for arr in $SELECTED_ARRS; do
    [[ "$arr" == "seerr" ]] && continue
    arr_key="${APIKEY_BY_SLUG[$arr]:-}"
    if [[ -z "$arr_key" ]]; then
      msg_warn "Skipping download-client wiring for ${arr} — no API key."
      continue
    fi
    arr_ip="${IP_BY_SLUG[$arr]}"
    arr_port="${PORT_BY_SLUG[$arr]}"
    api_ver="${ARR_API_VER_BY_SLUG[$arr]}"

    case "$arr" in
      sonarr) category_field="tvCategory";    category_name="tv-sonarr" ;;
      radarr) category_field="movieCategory"; category_name="radarr"    ;;
      lidarr) category_field="musicCategory"; category_name="lidarr"    ;;
    esac

    for client in $SELECTED_CLIENTS; do
      url="http://${arr_ip}:${arr_port}/api/${api_ver}/downloadclient"

      if [[ "$client" == "qbittorrent" ]]; then
        payload=$(jq -n \
          --arg host "${IP_BY_SLUG[qbittorrent]}" \
          --argjson port 8090 \
          --arg user "${USER_BY_SLUG[qbittorrent]}" \
          --arg pass "${PASS_BY_SLUG[qbittorrent]}" \
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
          "${NAME_BY_SLUG[$arr]} -> qBittorrent" || true

      elif [[ "$client" == "sabnzbd" ]]; then
        sab_key="${APIKEY_BY_SLUG[sabnzbd]:-}"
        if [[ -z "$sab_key" ]]; then
          record_failure "${NAME_BY_SLUG[$arr]} -> SABnzbd  FAIL (no sab apikey)"
          continue
        fi
        payload=$(jq -n \
          --arg host "${IP_BY_SLUG[sabnzbd]}" \
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
          "${NAME_BY_SLUG[$arr]} -> SABnzbd" || true
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

  local -a lines=()
  lines+=( "============================================================" )
  lines+=( "  arr Stack — Provisioning Summary" )
  lines+=( "  Generated: ${now}" )
  lines+=( "  Host:      ${host}" )
  lines+=( "============================================================" )
  lines+=( "" )
  lines+=( "[Shared settings]" )
  lines+=( "  Bridge:     ${var_bridge}" )
  lines+=( "  Gateway:    ${var_gateway}" )
  lines+=( "  CIDR:       /${var_cidr}" )
  lines+=( "  CT storage: ${var_container_storage}" )
  lines+=( "  Template:   ${var_template_storage}" )
  lines+=( "" )

  lines+=( "[Containers]" )
  local s
  for s in "${ORDERED_SLUGS[@]}"; do
    lines+=( "$(printf '  %-12s ctid=%-5s ip=%-16s url=http://%s:%s' \
      "$s" "${CTID_BY_SLUG[$s]}" "${IP_BY_SLUG[$s]}" "${IP_BY_SLUG[$s]}" "${PORT_BY_SLUG[$s]}")" )
  done
  lines+=( "" )

  lines+=( "[Credentials & API keys]" )
  for s in "${ORDERED_SLUGS[@]}"; do
    case "${KIND_BY_SLUG[$s]}" in
      indexer|arr)
        if [[ -n "${APIKEY_BY_SLUG[$s]:-}" ]]; then
          lines+=( "$(printf '  %-12s apikey: %s' "$s" "${APIKEY_BY_SLUG[$s]}")" )
        else
          lines+=( "$(printf '  %-12s apikey: (not extracted)' "$s")" )
        fi
        ;;
      client)
        if [[ "$s" == "qbittorrent" ]]; then
          lines+=( "$(printf '  %-12s user:   %s' "$s" "${USER_BY_SLUG[qbittorrent]:-admin}")" )
          lines+=( "$(printf '  %-12s pass:   %s   (CHANGE THIS!)' "" "${PASS_BY_SLUG[qbittorrent]:-adminadmin}")" )
        elif [[ "$s" == "sabnzbd" ]]; then
          if [[ -n "${APIKEY_BY_SLUG[sabnzbd]:-}" ]]; then
            lines+=( "$(printf '  %-12s apikey: %s' "$s" "${APIKEY_BY_SLUG[sabnzbd]}")" )
          else
            lines+=( "$(printf '  %-12s apikey: (open web wizard at http://%s:7777 once)' "$s" "${IP_BY_SLUG[sabnzbd]}")" )
          fi
        fi
        ;;
      requests)
        lines+=( "$(printf '  %-12s (set during first-run web wizard)' "$s")" )
        ;;
    esac
  done
  lines+=( "" )

  lines+=( "[Wired automatically]" )
  if (( ${#WIRING_RESULTS[@]} == 0 )); then
    lines+=( "  (nothing)" )
  else
    local w
    for w in "${WIRING_RESULTS[@]}"; do lines+=( "  ${w}" ); done
  fi
  lines+=( "" )

  lines+=( "[Wiring failures]" )
  if (( ${#WIRING_FAILURES[@]} == 0 )); then
    lines+=( "  (none)" )
  else
    local f
    for f in "${WIRING_FAILURES[@]}"; do lines+=( "  ${f}" ); done
  fi
  lines+=( "" )

  lines+=( "[Manual steps still required]" )
  lines+=( "  1. Prowlarr: add indexers (none ship by default)." )
  lines+=( "  2. Sonarr/Radarr/Lidarr: set root folders and at least one quality profile." )
  if [[ " $SELECTED_CLIENTS " == *" qbittorrent "* ]]; then
    lines+=( "  3. qBittorrent: change admin password (default admin/adminadmin)." )
  fi
  if [[ " $SELECTED_ARRS " == *" seerr "* ]]; then
    lines+=( "  4. Seerr: open http://${IP_BY_SLUG[seerr]}:5055, complete the first-run wizard, then add:" )
    for s in $SELECTED_ARRS; do
      [[ "$s" == "seerr" ]] && continue
      [[ "$s" == "lidarr" ]] && continue
      lines+=( "       ${NAME_BY_SLUG[$s]} at http://${IP_BY_SLUG[$s]}:${PORT_BY_SLUG[$s]}  apikey: ${APIKEY_BY_SLUG[$s]:-<missing>}" )
    done
  fi
  lines+=( "" )
  lines+=( "Summary written to ${SUMMARY_FILE} (chmod 600)." )
  lines+=( "============================================================" )

  local body
  body=$(printf '%s\n' "${lines[@]}")

  echo
  echo "$body"

  ( umask 077; printf '%s\n' "$body" > "$SUMMARY_FILE" )
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
