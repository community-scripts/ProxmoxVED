#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: kauezatarin
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.spigotmc.org/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y git samba
msg_ok "Installed Dependencies"

mc_version=${mc_version:-latest}

java_version=25
if [[ "$mc_version" =~ ^1\.(17|18|19|20)(\.|$) ]]; then
    java_version=21
fi

JAVA_VERSION="${java_version}" setup_java

msg_info "Building SpigotMC (Patience)"
mkdir -p /opt/spigotmc-build
cd /opt/spigotmc-build
wget -qO BuildTools.jar https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar
$STD java -jar BuildTools.jar --rev "$mc_version"
mkdir -p /opt/spigotmc
mv spigot-*.jar /opt/spigotmc/spigot.jar
cd /opt/spigotmc
rm -rf /opt/spigotmc-build
msg_ok "Built SpigotMC"

msg_info "Setting up Application"
# Automatically accept EULA
cat <<EOF > eula.txt
eula=true
EOF

# Configure RCON for remote commands
rcon_pass=$(openssl rand -hex 8)
cat <<EOF > server.properties
enable-rcon=true
rcon.password=${rcon_pass}
rcon.port=25575
EOF
msg_ok "Configured Application (RCON enabled)"

msg_info "Setting up Samba Share"
# Disable default homes share so the root folder isn't shared
sed -i 's/\[homes\]/\[homes_disabled\]/g' /etc/samba/smb.conf
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
java_path=$(which java)

cat <<EOF > /etc/systemd/system/spigotmc.service
[Unit]
Description=SpigotMC Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/spigotmc
ExecStart=${java_path} -Xms1024M -Xmx2048M -jar spigot.jar nogui
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now spigotmc
msg_ok "Created Service"

msg_info "Creating README Documentation"
cat <<'EOF' > /opt/spigotmc/README.md
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
