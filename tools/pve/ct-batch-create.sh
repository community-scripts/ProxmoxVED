#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE

set -eEuo pipefail

BL='\033[36m'
GN='\033[1;92m'
YW='\033[1;93m'
RD='\033[01;31m'
CL='\033[m'

var_repo="${var_repo:-}"
var_mode="${var_mode:-}"
var_apps="${var_apps:-}"
var_refresh_cache="${var_refresh_cache:-no}"
var_cache_ttl="${var_cache_ttl:-21600}"
var_template_storage="${var_template_storage:-}"
var_container_storage="${var_container_storage:-}"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
CACHE_DIR="/tmp/community-scripts-ct-batch-cache"

header_info() {
  clear
  cat <<"EOF"
   ______ _______   ____        __       __      ______                __
  / ____//_  __/ | / / /_  ____/ /______/ /_    / ____/_______  ____ _/ /____  _____
 / /      / /  | |/ / __ \/ __  / ___/ __ \    / /   / ___/ _ \/ __ `/ __/ _ \/ ___/
/ /___   / /   |   / /_/ / /_/ (__  ) / / /   / /___/ /  /  __/ /_/ / /_/  __/ /
\____/  /_/    |__/_.___/\__,_/____/_/ /_/    \____/_/   \___/\__,_/\__/\___/_/

EOF
}

msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
msg_ok() { echo -e "${GN}[OK]${CL} $1"; }
msg_warn() { echo -e "${YW}[WARN]${CL} $1"; }
msg_error() { echo -e "${RD}[ERROR]${CL} $1"; }

ensure_dependencies() {
  if ! command -v curl >/dev/null 2>&1; then
    apt update >/dev/null 2>&1
    apt install -y curl >/dev/null 2>&1
  fi

  if ! command -v whiptail >/dev/null 2>&1; then
    apt update >/dev/null 2>&1
    apt install -y whiptail >/dev/null 2>&1
  fi
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    msg_error "Run this script as root."
    exit 1
  fi
}

select_repo() {
  if [[ -n "$var_repo" ]]; then
    case "${var_repo,,}" in
    ve | proxmoxve) REPO_NAME="ProxmoxVE" ;;
    ved | proxmoxved) REPO_NAME="ProxmoxVED" ;;
    *)
      msg_error "Invalid var_repo='$var_repo'. Use: ve|ved"
      exit 1
      ;;
    esac
    return
  fi

  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "Repository" \
    --menu "Choose script source:" 14 60 2 \
    "ProxmoxVE" "community-scripts/ProxmoxVE" \
    "ProxmoxVED" "community-scripts/ProxmoxVED" \
    3>&1 1>&2 2>&3) || exit 0

  REPO_NAME="$choice"
}

select_mode() {
  if [[ -n "$var_mode" ]]; then
    case "${var_mode,,}" in
    generated | mydefaults) INSTALL_MODE="${var_mode,,}" ;;
    *)
      msg_error "Invalid var_mode='$var_mode'. Use: generated|mydefaults"
      exit 1
      ;;
    esac
    return
  fi

  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "Install Mode" \
    --menu "Choose unattended mode:" 13 66 2 \
    "generated" "Auto-generated defaults" \
    "mydefaults" "Use /usr/local/community-scripts/default.vars" \
    3>&1 1>&2 2>&3) || exit 0

  INSTALL_MODE="$choice"
}

cache_file_for_repo() {
  echo "${CACHE_DIR}/${REPO_NAME,,}-apps-sorted.txt"
}

is_cache_valid() {
  local cache_file="$1"
  [[ -f "$cache_file" ]] || return 1

  local now age
  now=$(date +%s)
  age=$((now - $(stat -c %Y "$cache_file")))
  [[ "$age" -lt "$var_cache_ttl" ]]
}

pick_default_storage() {
  local content="$1"
  local selected=""

  selected=$(pvesm status -content "$content" 2>/dev/null | awk 'NR>1 && $1=="local" {print $1; exit}')
  [[ -z "$selected" ]] && selected=$(pvesm status -content "$content" 2>/dev/null | awk 'NR>1 && $1=="local-lvm" {print $1; exit}')
  [[ -z "$selected" ]] && selected=$(pvesm status -content "$content" 2>/dev/null | awk 'NR>1 {print $1; exit}')

  echo "$selected"
}

prepare_unattended_storage() {
  if [[ -z "$var_template_storage" ]]; then
    var_template_storage=$(pick_default_storage vztmpl)
  fi

  if [[ -z "$var_container_storage" ]]; then
    var_container_storage=$(pick_default_storage rootdir)
  fi

  [[ -n "$var_template_storage" ]] && msg_info "Template storage: ${var_template_storage}"
  [[ -n "$var_container_storage" ]] && msg_info "Container storage: ${var_container_storage}"
}

fetch_ct_list() {
  mkdir -p "$CACHE_DIR"

  local cache_file
  cache_file=$(cache_file_for_repo)

  if [[ "$var_refresh_cache" != "yes" ]] && is_cache_valid "$cache_file"; then
    msg_ok "Using cached app list (${cache_file})"
    cp "$cache_file" "$TEMP_DIR/apps-sorted.txt"
    return
  fi

  local api_url="https://api.github.com/repos/community-scripts/${REPO_NAME}/contents/ct?ref=main"

  msg_info "Refreshing CT list from ${REPO_NAME}..."
  curl -fsSL "$api_url" >"$TEMP_DIR/ct.json"

  sed -n 's/.*"name": "\([^"]*\.sh\)".*/\1/p' "$TEMP_DIR/ct.json" |
    sort -f >"$TEMP_DIR/slugs.txt"

  if [[ ! -s "$TEMP_DIR/slugs.txt" ]]; then
    msg_error "No CT scripts found in ${REPO_NAME}."
    exit 1
  fi

  : >"$TEMP_DIR/apps.txt"
  local total index
  total=$(wc -l <"$TEMP_DIR/slugs.txt")
  index=0

  while IFS= read -r script_file; do
    index=$((index + 1))
    local slug="${script_file%.sh}"
    local raw_url="https://raw.githubusercontent.com/community-scripts/${REPO_NAME}/main/ct/${script_file}"
    local app_name

    msg_info "[${index}/${total}] Reading app name for ${slug}"
    app_name=$(curl -fsSL "$raw_url" | sed -n 's/^APP="\([^"]*\)".*/\1/p' | head -n1 || true)
    [[ -z "$app_name" ]] && app_name="$slug"

    printf '%s|%s\n' "$slug" "$app_name" >>"$TEMP_DIR/apps.txt"
  done <"$TEMP_DIR/slugs.txt"

  sort -f -t '|' -k2,2 -k1,1 "$TEMP_DIR/apps.txt" >"$TEMP_DIR/apps-sorted.txt"
  cp "$TEMP_DIR/apps-sorted.txt" "$cache_file"
  msg_ok "Cached app list written to ${cache_file}"
}

select_apps() {
  if [[ -n "$var_apps" ]]; then
    SELECTED_APPS=$(echo "$var_apps" | tr ',' ' ')
    return
  fi

  local menu_items=()
  while IFS='|' read -r slug app_name; do
    menu_items+=("$slug" "$app_name" "OFF")
  done <"$TEMP_DIR/apps-sorted.txt"

  if [[ ${#menu_items[@]} -eq 0 ]]; then
    msg_error "No app entries available for selection."
    exit 1
  fi

  local choice
  choice=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "CT Batch Creator (${REPO_NAME})" \
    --checklist "Select one or more CT scripts (alphabetical by app name):" 30 90 20 \
    "${menu_items[@]}" 3>&1 1>&2 2>&3) || exit 0

  SELECTED_APPS=$(echo "$choice" | tr -d '"')

  if [[ -z "$SELECTED_APPS" ]]; then
    msg_warn "No apps selected."
    exit 0
  fi
}

run_selected_apps() {
  local selected_count
  selected_count=$(echo "$SELECTED_APPS" | wc -w)

  msg_info "Starting ${selected_count} deployment(s) from ${REPO_NAME} with mode=${INSTALL_MODE}"
  prepare_unattended_storage

  local failed_apps=()
  local done_count=0
  for slug in $SELECTED_APPS; do
    local script_url="https://raw.githubusercontent.com/community-scripts/${REPO_NAME}/main/ct/${slug}.sh"
    local script_file="$TEMP_DIR/${slug}.sh"
    done_count=$((done_count + 1))

    msg_info "[${done_count}/${selected_count}] Downloading ${slug}"
    curl -fsSL "$script_url" >"$script_file"

    msg_info "[${done_count}/${selected_count}] Deploying ${slug}"
    if MODE="$INSTALL_MODE" mode="$INSTALL_MODE" PHS_SILENT=1 \
      var_template_storage="$var_template_storage" \
      var_container_storage="$var_container_storage" \
      bash "$script_file"; then
      msg_ok "Finished ${slug}"
    else
      msg_error "Failed ${slug}"
      failed_apps+=("$slug")
    fi
  done

  if [[ ${#failed_apps[@]} -gt 0 ]]; then
    msg_warn "Completed with failures: ${failed_apps[*]}"
    exit 1
  fi

  msg_ok "All selected CTs were processed successfully."
}

main() {
  header_info
  check_root
  ensure_dependencies
  select_repo
  select_mode
  fetch_ct_list
  select_apps
  run_selected_apps
}

main "$@"
