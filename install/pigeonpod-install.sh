#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/aizhimou/pigeon-pod

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_ffmpeg
NODE_VERSION="22" setup_nodejs
JAVA_VERSION="17" setup_java

# after setup_java, so Temurin satisfies maven's Java dependency instead of pulling in OpenJDK
msg_info "Installing Dependencies"
$STD apt install -y maven
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "deno" "denoland/deno" "prebuild" "latest" "/usr/local/bin" "deno-$(arch_resolve "x86_64" "aarch64")-unknown-linux-gnu.zip"
fetch_and_deploy_gh_release "yt-dlp" "yt-dlp/yt-dlp" "singlefile" "latest" "/usr/local/bin" "yt-dlp_$(arch_resolve "linux" "linux_aarch64")"
fetch_and_deploy_gh_release "pigeonpod" "aizhimou/pigeon-pod" "tarball"

msg_info "Building PigeonPod"
cd /opt/pigeonpod/frontend
$STD npm ci
$STD npm run build
mv /opt/pigeonpod/frontend/dist /opt/pigeonpod/backend/src/main/resources/static
cd /opt/pigeonpod/backend
$STD mvn -B clean package -DskipTests
mv /opt/pigeonpod/backend/target/pigeon-pod-*.jar /opt/pigeonpod/pigeon-pod.jar
rm -rf /opt/pigeonpod/frontend/node_modules /opt/pigeonpod/backend/target
msg_ok "Built PigeonPod"

msg_info "Configuring PigeonPod"
mkdir -p /opt/pigeonpod_data
cat <<EOF >/opt/pigeonpod_data/.env
SPRING_DATASOURCE_URL="jdbc:sqlite:/opt/pigeonpod_data/pigeon-pod.db?journal_mode=WAL&synchronous=NORMAL&cache_size=10000&temp_store=memory&busy_timeout=3000"
PIGEON_BASE_URL=http://${LOCAL_IP}:8080
PIGEON_AUDIO_FILE_PATH=/opt/pigeonpod_data/audio/
PIGEON_VIDEO_FILE_PATH=/opt/pigeonpod_data/video/
PIGEON_COVER_FILE_PATH=/opt/pigeonpod_data/cover/
PIGEON_SSLFILEPATH=/opt/pigeonpod_data/ssl/
PIGEON_YTDLP_MANAGEDROOT=/opt/pigeonpod_data/tools/yt-dlp
EOF
chmod 600 /opt/pigeonpod_data/.env
msg_ok "Configured PigeonPod"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/pigeonpod.service
[Unit]
Description=PigeonPod
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/pigeonpod_data
EnvironmentFile=/opt/pigeonpod_data/.env
Environment=LANG=C.UTF-8
ExecStart=/usr/bin/java -Dfile.encoding=UTF-8 -jar /opt/pigeonpod/pigeon-pod.jar
SuccessExitStatus=143
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now pigeonpod
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
