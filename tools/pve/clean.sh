#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

set -euo pipefail

function header_info() {
  clear
  cat <<"EOF"
   ________                    __   _  ________
  / ____/ /__  ____ _____     / /  | |/ / ____/
 / /   / / _ \/ __ `/ __ \   / /   |   / /
/ /___/ /  __/ /_/ / / / /  / /___/   / /___
\____/_/\___/\__,_/_/ /_/  /_____/_/|_\____/

EOF
}

BL="\033[36m"
GN="\033[1;92m"
CL="\033[m"
name=$(hostname)

header_info
echo -e "${BL}[Info]${GN} Cleaning $name${CL} \n"

# OS-Detection
if [ -f /etc/alpine-release ]; then
  OS="alpine"
elif [ -f /etc/debian_version ] || grep -qi ubuntu /etc/issue 2>/dev/null; then
  OS="debian"
else
  OS="unknown"
fi

# Universal Cleaning
function clean_universal() {
  # Caches
  find /var/cache/ -type f -delete 2>/dev/null || true
  # Logs
  find /var/log/ -type f -delete 2>/dev/null || true
  # Tmp
  find /tmp/ -mindepth 1 -delete 2>/dev/null || true
  find /var/tmp/ -mindepth 1 -delete 2>/dev/null || true
  # User Trash (Desktop-Umgebungen)
  for u in /home/* /root; do
    find "$u/.local/share/Trash/" -type f -delete 2>/dev/null || true
  done
}

clean_universal

if [ "$OS" = "alpine" ]; then
  echo -e "${BL}[Info]${GN} Alpine detected: Cleaning apk cache...${CL}"
  rm -rf /var/cache/apk/* 2>/dev/null || true
  apk cache clean 2>/dev/null || true
  rm -rf /etc/apk/cache/* 2>/dev/null || true

elif [ "$OS" = "debian" ]; then
  echo -e "${BL}[Info]${GN} Debian/Ubuntu detected: Cleaning apt and journal...${CL}"
  apt-get -y autoremove --purge >/dev/null 2>&1 || true
  apt-get -y autoclean >/dev/null 2>&1 || true
  apt-get -y clean >/dev/null 2>&1 || true
  journalctl --vacuum-time=2d --rotate >/dev/null 2>&1 || true
  rm -rf /var/lib/apt/lists/* 2>/dev/null || true
  apt-get update >/dev/null 2>&1 || true
fi

echo -e "${GN}Cleanup completed for $name ($OS)${CL}\n"
