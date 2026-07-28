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
$STD apt-get install -y curl sudo mc jq git wget samba gnupg
msg_ok "Installed Dependencies"

msg_info "Installing Azul Zulu OpenJDK 25"
curl -s https://repos.azul.com/azul-repo.key | gpg --dearmor > /usr/share/keyrings/azul.gpg
echo "deb [signed-by=/usr/share/keyrings/azul.gpg] https://repos.azul.com/zulu/deb stable main" > /etc/apt/sources.list.d/zulu.list
$STD apt-get update
$STD apt-get install -y zulu25-jdk
msg_ok "Installed Azul Zulu OpenJDK 25"

read -rp "${TAB3}Which SpigotMC version would you like to install? (e.g. 1.20.4) [Default: latest]: " MC_VERSION || true
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
RCON_PASS=$(openssl rand -hex 8)
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
   valid users = root
EOF
(echo "spigot"; echo "spigot") | smbpasswd -s -a root
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

msg_info "Creating README Documentation"
cat <<'EOF' > /root/README.md
# SpigotMC LXC Container Documentation

Welcome to your SpigotMC container! Here are some useful commands and instructions.

## 1. Managing the Server
This server runs as a systemd service named `spigotmc`.
- **Start the server:** `systemctl start spigotmc`
- **Stop the server:** `systemctl stop spigotmc`
- **Restart the server:** `systemctl restart spigotmc`
- **Check server status:** `systemctl status spigotmc`
- **View live console logs:** `journalctl -fu spigotmc`

## 2. Changing Allocated RAM
To change the maximum amount of RAM the Minecraft server can use:
1. Open the service file in an editor: `nano /etc/systemd/system/spigotmc.service`
2. Find the `ExecStart=` line.
3. Change `-Xmx2048M` (or whatever value is there) to your desired maximum RAM (e.g., `-Xmx4096M` for 4GB).
4. Save and exit (Press `CTRL+X`, then `Y`, then `Enter`).
5. Reload systemd: `systemctl daemon-reload`
6. Restart the server: `systemctl restart spigotmc`

## 3. Changing the SMB (Samba) Password
The default Samba username is `root` with password `spigot`. To change it:
1. Run this command: `smbpasswd -a root`
2. Type your new password and press Enter.
3. Retype the new password and press Enter.
You can now access your files using the new password over the network.
EOF
msg_ok "Created README Documentation"

motd_ssh
customize
cleanup_lxc
