#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/automatic-ripping-machine/automatic-ripping-machine

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  abcde \
  at \
  build-essential \
  cdparanoia \
  default-jre-headless \
  eject \
  ffmpeg \
  flac \
  glyrc \
  handbrake-cli \
  imagemagick \
  libavcodec-dev \
  libavcodec-extra \
  libcurl4-openssl-dev \
  libdiscid-dev \
  libexpat1-dev \
  libffi-dev \
  libgl1-mesa-dev \
  libssl-dev \
  lsdvd \
  pkg-config \
  qtbase5-dev \
  zlib1g-dev
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv

msg_info "Building MakeMKV (Patience)"
MAKEMKV_VER=$(curl -sL https://www.makemkv.com/download/ | grep -oP 'makemkv-bin-\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
cd /tmp
$STD curl -fsSL -o makemkv-oss.tar.gz "https://www.makemkv.com/download/makemkv-oss-${MAKEMKV_VER}.tar.gz"
$STD curl -fsSL -o makemkv-bin.tar.gz "https://www.makemkv.com/download/makemkv-bin-${MAKEMKV_VER}.tar.gz"
tar xf makemkv-oss.tar.gz
tar xf makemkv-bin.tar.gz
cd "makemkv-oss-${MAKEMKV_VER}"
$STD ./configure
$STD make -j"$(nproc)"
$STD make install
cd "/tmp/makemkv-bin-${MAKEMKV_VER}"
mkdir -p tmp
echo "accepted" >tmp/eula_accepted
$STD make install
ldconfig
cd /
rm -rf /tmp/makemkv-*
msg_ok "Built MakeMKV ${MAKEMKV_VER}"

fetch_and_deploy_gh_release "arm" "automatic-ripping-machine/automatic-ripping-machine" "tarball"

msg_info "Setting up Python Environment"
cd /opt/arm
$STD uv venv /opt/arm/venv
$STD uv pip install --python /opt/arm/venv/bin/python \
  -r <(curl -fsSL https://raw.githubusercontent.com/automatic-ripping-machine/arm-dependencies/main/requirements.txt) \
  -r requirements.txt
msg_ok "Set up Python Environment"

msg_info "Configuring Application"
cp /opt/arm/setup/arm.yaml /opt/arm/arm.yaml
cp /opt/arm/setup/.abcde.conf /etc/.abcde.conf
mkdir -p /etc/arm/config
ln -sf /opt/arm/arm.yaml /etc/arm/config/arm.yaml
ln -sf /etc/.abcde.conf /etc/arm/config/abcde.conf

mkdir -p /home/arm/{logs/progress,media/{transcode,completed,raw},db}

for i in $(seq 0 4); do
  mkdir -p "/mnt/dev/sr${i}"
  grep -qF "/dev/sr${i}" /etc/fstab || echo "/dev/sr${i}  /mnt/dev/sr${i}  udf,iso9660  defaults,users,utf8,ro,noauto  0  0" >>/etc/fstab
done

chmod +x /opt/arm/scripts/thickclient/*.sh 2>/dev/null || true
cp /opt/arm/setup/51-automatic-ripping-machine-venv.rules /etc/udev/rules.d/
sed -i "s|/bin/su -l.*-s /bin/bash.*|/opt/arm/scripts/thickclient/arm_venv_wrapper.sh %k\"|" /etc/udev/rules.d/51-automatic-ripping-machine-venv.rules 2>/dev/null || true
msg_ok "Configured Application"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/armui.service
[Unit]
Description=ARM Web UI Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/arm
ExecStart=/opt/arm/venv/bin/python3 /opt/arm/arm/runui.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now atd armui
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
