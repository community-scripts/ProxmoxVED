#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: kauezatarin
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.spigotmc.org/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl sudo mc jq git wget mcrcon samba gnupg
msg_ok "Installed Dependencies"

msg_info "Installing Azul Zulu OpenJDK 25"
wget -qO /etc/apt/trusted.gpg.d/zulu-repo.asc https://repos.azul.com/azul-repo.key
echo "deb http://repos.azul.com/zulu/apt all main" > /etc/apt/sources.list.d/zulu.list
$STD apt-get update
$STD apt-get install -y zulu25-jdk
msg_ok "Installed Azul Zulu OpenJDK 25"

read -rp "${TAB3}Which SpigotMC version would you like to install? (e.g. 1.20.4) [Default: latest]: " MC_VERSION
MC_VERSION=${MC_VERSION:-latest}

msg_info "Building SpigotMC (This will take a while)"
mkdir -p /opt/spigotmc-build
cd /opt/spigotmc-build
wget -qO BuildTools.jar https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar
$STD java -jar BuildTools.jar --rev $MC_VERSION
mkdir -p /opt/spigotmc
mv spigot-*.jar /opt/spigotmc/
cd /opt/spigotmc
rm -rf /opt/spigotmc-build
msg_ok "Built SpigotMC"

msg_info "Setting up Application"
# Automatically accept EULA
echo "eula=true" > eula.txt

# Configure RCON for remote commands
RCON_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
cat <<EOF > server.properties
enable-rcon=true
rcon.password=$RCON_PASS
rcon.port=25575
EOF
msg_ok "Set up Application"

msg_info "Setting up Samba Share"
cat <<EOF >> /etc/samba/smb.conf
[SpigotMC]
   path = /opt/spigotmc
   browseable = yes
   read only = no
   guest ok = yes
   force user = root
EOF
systemctl restart smbd
msg_ok "Set up Samba Share"

msg_info "Creating Service"
SPIGOT_JAR=$(ls spigot-*.jar | head -n 1)
JAVA_PATH=$(which java)

cat <<EOF > /etc/systemd/system/spigotmc.service
[Unit]
Description=SpigotMC Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/spigotmc
ExecStart=${JAVA_PATH} -Xms1024M -Xmx2048M -jar ${SPIGOT_JAR} nogui
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now spigotmc
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
