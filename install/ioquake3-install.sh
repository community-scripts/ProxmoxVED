#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: geedoes
# License: MIT
# https://github.com/community-scripts/ProxmoxVE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
catch_errors
setting_up_container
network_check
update_os

function msg_info() {
    local msg="$1"
    echo -ne " ${HOLD} ${YW}${msg}..."
}
function msg_ok() {
    local msg="$1"
    echo -e "${BGN} ${GN}${msg}${CL}"
}

msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get install -y curl wget git unzip build-essential cmake libsdl2-dev libcurl4-openssl-dev zlib1g-dev pkg-config ca-certificates
msg_ok "Installed Dependencies"

msg_info "Setting up environment"
$STD useradd -r -m -d /opt/ioquake3 -s /usr/sbin/nologin quake3
mkdir -p /opt/ioquake3/baseq3
msg_ok "Environment setup complete"

echo -e " \033[1;33mCompiling ioquake3 dedicated server via CMake (This takes a minute)\033[0m"

rm -rf /opt/ioq3-src
$STD git clone --depth 1 https://github.com/ioquake/ioq3.git /opt/ioq3-src

cd /opt/ioq3-src
mkdir -p build
cd build

$STD cmake -DBUILD_CLIENT=OFF -DBUILD_SERVER=ON ..

$STD make -j$(nproc)

SERVER_BIN=$(find . -maxdepth 2 -type f -name "ioq3ded*" -executable | head -n 1)

if [ -z "$SERVER_BIN" ]; then
    echo -e "\n\033[1;31mERROR: Compilation finished but ioq3ded binary was not found!\033[0m"
    exit 1
fi

cp "$SERVER_BIN" /opt/ioquake3/ioq3ded
cd /opt/ioquake3
rm -rf /opt/ioq3-src
chmod +x /opt/ioquake3/ioq3ded
msg_ok "ioquake3 compiled successfully"

msg_info "Downloading ioquake3 latest patch pk3s"
wget -qO /tmp/patch.zip "https://files.ioquake3.org/quake3-latest-pk3s.zip"
unzip -q /tmp/patch.zip -d /tmp/patch_unzip
cp -a /tmp/patch_unzip/quake3-latest-pk3s/* /opt/ioquake3/
rm -rf /tmp/patch.zip /tmp/patch_unzip
msg_ok "Patch pk3s extracted"

msg_info "Downloading start_server.sh"
wget -qO /opt/ioquake3/start_server.sh "https://raw.githubusercontent.com/ioquake/ioq3/master/misc/linux/start_server.sh"
chmod +x /opt/ioquake3/start_server.sh
msg_ok "start_server.sh downloaded"

msg_info "Creating server.cfg"
cat <<EOF > /opt/ioquake3/baseq3/server.cfg
seta sv_hostname "Proxmox ioquake3 Server"
seta sv_maxclients 16
seta g_motd "Welcome to ioquake3 LXC!"
seta g_quadfactor 3
seta g_gametype 0
seta timelimit 15
seta fraglimit 20
seta g_weaponrespawn 5
seta g_inactivity 3000
seta g_forcerespawn 0
seta g_log "games.log"
seta logfile 1
seta rconpassword "changeme"
seta com_legacyprotocol 68
map q3dm17
EOF
msg_ok "server.cfg created"

msg_info "Setting permissions"
chown -R quake3:quake3 /opt/ioquake3
msg_ok "Permissions applied"

msg_info "Creating systemd service"
cat <<EOF > /etc/systemd/system/ioquake3.service
[Unit]
Description=ioquake3 Dedicated Server
After=network.target

[Service]
Type=simple
User=quake3
WorkingDirectory=/opt/ioquake3
ExecStart=/opt/ioquake3/ioq3ded +set dedicated 1 +set com_hunkMegs 128 +set net_port 27960 +exec server.cfg
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now ioquake3
msg_ok "Systemd service created and started"

echo "ioquake3 Dedicated Server LXC" > /etc/motd

msg_ok "ioquake3 installation successful!"
echo -e "\n\033[1;33m================= IMPORTANT INSTRUCTIONS =================\033[0m"
echo -e "To play, you must upload your retail \033[1;32mpak0.pk3\033[0m file to the server."
echo -e "Upload Path: \033[1;36m/opt/ioquake3/baseq3/\033[0m"
echo -e "\nYou can use SCP to upload the file. Once uploaded, restart the service:"
echo -e "\033[1;34m  systemctl restart ioquake3\033[0m"
echo -e "\033[1;33m==========================================================\033[0m\n"
