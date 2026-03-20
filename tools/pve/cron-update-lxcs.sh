#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT
# https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
#
# This script manages a local cron job for automatic LXC container OS updates.
# The update script is downloaded once, displayed for review, and installed
# locally. Cron runs the local copy — no remote code execution at runtime.
#
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/tools/pve/cron-update-lxcs.sh)"

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main"
SCRIPT_URL="${REPO_URL}/tools/pve/update-lxcs-cron.sh"
LOCAL_SCRIPT="/usr/local/bin/update-lxcs.sh"
CONF_FILE="/etc/update-lxcs.conf"
LOG_FILE="/var/log/update-lxcs-cron.log"
CRON_ENTRY="0 0 * * 0 ${LOCAL_SCRIPT} >>${LOG_FILE} 2>&1"

clear
cat <<"EOF"
   ______                    __  __          __      __          __   _  ________
  / ____/________  ____     / / / /___  ____/ /___ _/ /____     / /  | |/ / ____/____
 / /   / ___/ __ \/ __ \   / / / / __ \/ __  / __ `/ __/ _ \   / /   |   / /   / ___/
/ /___/ /  / /_/ / / / /  / /_/ / /_/ / /_/ / /_/ / /_/  __/  / /___/   / /___(__  )
\____/_/   \____/_/ /_/   \____/ .___/\__,_/\__,_/\__/\___/  /_____/_/|_\____/____/
                              /_/
EOF

info() { echo -e "\n \e[36m[Info]\e[0m $1"; }
ok() { echo -e " \e[32m[OK]\e[0m $1"; }
err() { echo -e " \e[31m[Error]\e[0m $1" >&2; }

confirm() {
  local prompt="${1:-Proceed?}"
  while true; do
    read -rp " ${prompt} (y/n): " yn
    case $yn in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    *) echo "  Please answer yes or no." ;;
    esac
  done
}

download_script() {
  local tmp
  tmp=$(mktemp)
  if ! curl -fsSL -o "$tmp" "$SCRIPT_URL"; then
    err "Failed to download script from:\n  ${SCRIPT_URL}"
    rm -f "$tmp"
    return 1
  fi
  echo "$tmp"
}

review_script() {
  local file="$1"
  local hash
  hash=$(sha256sum "$file" | awk '{print $1}')
  echo ""
  echo -e " \e[1;33m─── Script Content ───────────────────────────────────────────\e[0m"
  cat "$file"
  echo -e " \e[1;33m──────────────────────────────────────────────────────────────\e[0m"
  echo -e " \e[36mSHA256:\e[0m ${hash}"
  echo -e " \e[36mSource:\e[0m ${SCRIPT_URL}"
  echo ""
}

remove_legacy_cron() {
  if crontab -l -u root 2>/dev/null | grep -q "update-lxcs-cron.sh"; then
    (crontab -l -u root 2>/dev/null | grep -v "update-lxcs-cron.sh") | crontab -u root -
    ok "Removed legacy curl-based cron entry"
  fi
}

add() {
  info "Downloading update script for review..."
  local tmp
  tmp=$(download_script) || exit 1

  review_script "$tmp"

  if ! confirm "Install this script to ${LOCAL_SCRIPT} and add cron schedule?"; then
    rm -f "$tmp"
    echo " Aborted."
    exit 0
  fi

  remove_legacy_cron

  install -m 0755 "$tmp" "$LOCAL_SCRIPT"
  rm -f "$tmp"
  ok "Installed script to ${LOCAL_SCRIPT}"

  if [[ ! -f "$CONF_FILE" ]]; then
    cat >"$CONF_FILE" <<'CONF'
# Configuration for automatic LXC container OS updates.
# Add container IDs to exclude from updates (comma-separated):
# EXCLUDE=100,101,102
EXCLUDE=
CONF
    ok "Created config ${CONF_FILE}"
  fi

  (
    crontab -l -u root 2>/dev/null | grep -v "${LOCAL_SCRIPT}"
    echo "${CRON_ENTRY}"
  ) | crontab -u root -
  ok "Added cron schedule: Every Sunday at midnight"
  echo ""
  echo -e " \e[36mLocal script:\e[0m ${LOCAL_SCRIPT}"
  echo -e " \e[36mConfig:\e[0m      ${CONF_FILE}"
  echo -e " \e[36mLog file:\e[0m    ${LOG_FILE}"
  echo ""
}

remove() {
  if crontab -l -u root 2>/dev/null | grep -q "${LOCAL_SCRIPT}"; then
    (crontab -l -u root 2>/dev/null | grep -v "${LOCAL_SCRIPT}") | crontab -u root -
    ok "Removed cron schedule"
  fi
  remove_legacy_cron
  [[ -f "$LOCAL_SCRIPT" ]] && rm -f "$LOCAL_SCRIPT" && ok "Removed ${LOCAL_SCRIPT}"
  [[ -f "$LOG_FILE" ]] && rm -f "$LOG_FILE" && ok "Removed ${LOG_FILE}"
  echo -e "\n Cron Update LXCs has been fully removed."
  echo -e " \e[90mNote: ${CONF_FILE} was kept (remove manually if desired).\e[0m"
}

update_script() {
  if [[ ! -f "$LOCAL_SCRIPT" ]]; then
    err "No local script found at ${LOCAL_SCRIPT}. Use 'Add' first."
    exit 1
  fi

  info "Downloading latest version..."
  local tmp
  tmp=$(download_script) || exit 1

  if command -v diff &>/dev/null; then
    local changes
    changes=$(diff --color=auto "$LOCAL_SCRIPT" "$tmp" 2>/dev/null || true)
    if [[ -z "$changes" ]]; then
      ok "Script is already up-to-date (no changes)."
      rm -f "$tmp"
      return
    fi
    echo ""
    echo -e " \e[1;33m─── Changes ──────────────────────────────────────────────────\e[0m"
    echo "$changes"
    echo -e " \e[1;33m──────────────────────────────────────────────────────────────\e[0m"
  else
    review_script "$tmp"
  fi

  local new_hash old_hash
  new_hash=$(sha256sum "$tmp" | awk '{print $1}')
  old_hash=$(sha256sum "$LOCAL_SCRIPT" | awk '{print $1}')
  echo -e " \e[36mCurrent SHA256:\e[0m ${old_hash}"
  echo -e " \e[36mNew SHA256:\e[0m     ${new_hash}"
  echo ""

  if ! confirm "Apply update?"; then
    rm -f "$tmp"
    echo " Aborted."
    return
  fi

  install -m 0755 "$tmp" "$LOCAL_SCRIPT"
  rm -f "$tmp"
  ok "Updated ${LOCAL_SCRIPT}"
}

view_script() {
  if [[ ! -f "$LOCAL_SCRIPT" ]]; then
    err "No local script found at ${LOCAL_SCRIPT}. Use 'Add' first."
    exit 1
  fi

  local hash
  hash=$(sha256sum "$LOCAL_SCRIPT" | awk '{print $1}')
  echo ""
  echo -e " \e[1;33m─── ${LOCAL_SCRIPT} ───\e[0m"
  cat "$LOCAL_SCRIPT"
  echo -e " \e[1;33m──────────────────────────────────────────────────────────────\e[0m"
  echo -e " \e[36mSHA256:\e[0m    ${hash}"
  echo -e " \e[36mInstalled:\e[0m $(stat -c '%y' "$LOCAL_SCRIPT" 2>/dev/null | cut -d. -f1)"
  echo ""
}

OPTIONS=(
  Add "Download, review & install cron schedule"
  Remove "Remove cron schedule & local script"
  Update "Update local script from repository"
  View "View currently installed script"
)

CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Cron Update LXCs" --menu "Select an option:" 12 68 4 \
  "${OPTIONS[@]}" 3>&1 1>&2 2>&3) || exit 0

case $CHOICE in
"Add") add ;;
"Remove") remove ;;
"Update") update_script ;;
"View") view_script ;;
esac
