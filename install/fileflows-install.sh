#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: kkroboth
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://fileflows.com/

# Import Functions und Setup
source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  jq
msg_ok "Installed Dependencies"

msg_info "Installing FFmpeg"
wget -q https://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_2024.9.1_all.deb
$STD dpkg -i deb-multimedia-keyring_2024.9.1_all.deb
cat <<EOF >/etc/apt/sources.list.d/backports.list
deb https://www.deb-multimedia.org bookworm main non-free
deb https://www.deb-multimedia.org bookworm-backports main
EOF
$STD apt update
DEBIAN_FRONTEND=noninteractive
$STD apt-get install -t bookworm-backports ffmpeg -y
rm -rf /etc/apt/sources.list.d/backports.list deb-multimedia-keyring_2016.8.1_all.deb
msg_ok "Installed FFmpeg"

msg_info "Setting Up Hardware Acceleration"

read -r -p "Do you need the intel-media-va-driver-non-free driver (Debian 12 only)? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  msg_info "Installing Hardware Acceleration (non-free)"
cat <<EOF >/etc/apt/sources.list.d/non-free.list

deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware

deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
$STD apt-get update
$STD apt-get -y install {intel-media-va-driver-non-free,ocl-icd-libopencl1,intel-opencl-icd,vainfo,intel-gpu-tools}
else
  msg_info "Installing Hardware Acceleration"
$STD apt-get -y install {va-driver-all,ocl-icd-libopencl1,intel-opencl-icd,vainfo,intel-gpu-tools}
fi

if [[ "$CTTYPE" == "0" ]]; then
  chgrp video /dev/dri
  chmod 755 /dev/dri
  chmod 660 /dev/dri/*
  $STD adduser $(id -u -n) video
  $STD adduser $(id -u -n) render
fi
msg_ok "Installed and Set Up Hardware Acceleration"

msg_info "Installing ASP.NET Core Runtime"
wget -q https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
$STD dpkg -i packages-microsoft-prod.deb
rm -rf packages-microsoft-prod.deb
$STD apt-get update
$STD apt-get install -y aspnetcore-runtime-8.0
msg_ok "Installed ASP.NET Core Runtime"

msg_info "Setup ${APPLICATION}"
temp_file=$(mktemp)
wget -q https://fileflows.com/downloads/zip -O $temp_file
unzip -q -d /opt/fileflows $temp_file
(cd /opt/fileflows/Server && dotnet FileFlows.Server.dll --systemd install --root true)
systemctl enable -q --now fileflows.service
msg_ok "Setup ${APPLICATION}"

msg_info "Setting ffmpeg variables in fileflows"

ffmpeg_uid=$(curl -s -X 'GET' "http://localhost:19200/api/variable/name/ffmpeg" -H 'accept: application/json' | jq -r '.Uid')
ffprobe_uid=$(curl -s -X 'GET' "http://localhost:19200/api/variable/name/ffprobe" -H 'accept: application/json' | jq -r '.Uid')

response=$(curl -s -X 'DELETE' \
  "http://localhost:19200/api/variable" \
  -H 'accept: */*' \
  -H 'Content-Type: application/json' \
  -d "{
  \"Uids\": [
    \"$ffmpeg_uid\",
    \"$ffprobe_uid\"
  ]
}")

ffmpeg_path=$(which ffmpeg)
ffprobe_path=$(which ffprobe)

response=$(curl -s -X 'POST' \
  "http://localhost:19200/api/variable" \
  -H 'accept: */*' \
  -H 'Content-Type: application/json' \
  -d "{\"Name\":\"ffmpeg\",\"Value\":\"$ffmpeg_path\"}")

response=$(curl -s -X 'POST' \
  "http://localhost:19200/api/variable" \
  -H 'accept: */*' \
  -H 'Content-Type: application/json' \
  -d "{\"Name\":\"ffprobe\",\"Value\":\"$ffprobe_path\"}")

msg_ok "ffmpeg and ffprobe variables have been updated successfully."

motd_ssh
customize

msg_info "Cleaning up"
rm -f $temp_file
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
