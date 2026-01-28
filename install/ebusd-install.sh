#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/john30/ebusd

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

setup_deb822_repo \
  "ebusd" \
  "https://raw.githubusercontent.com/john30/ebusd-debian/master/ebusd.gpg" \
  "https://repo.ebusd.eu/apt/default/bookworm/" \
  "bookworm" \
  "main"

msg_info "Installing ebusd"
$STD apt install -y ebusd
$STD systemctl enable ebusd
msg_ok "Installed ebusd"

cat <<EOF >~/ebusd-configuation-instructions.txt
Configuration instructions:

	1. Edit "/etc/default/ebusd" if necessary (especially if your device is not "/dev/ttyUSB0")
	2. Start the daemon with "systemctl start ebusd"
	3. Check the log file "/var/log/ebusd.log"
	4. Make the daemon autostart with "systemctl enable ebusd"

Working "/etc/default/ebusd" options for "ebus adapter shield v5":

EBUSD_OPTS="
	--pidfile=/run/ebusd.pid
	--latency=100
	--scanconfig
	--configpath=https://cfg.ebusd.eu/
	--accesslevel=*
	--pollinterval=30
	--device=ens:XXX.XXX.XXX.XXX:9999
	--mqtthost=XXX.XXX.XXX.XXX
	--mqttport=1883
	--mqttuser=XXXXXX
	--mqttpass=XXXXXX
	--mqttint=/etc/ebusd/mqtt-hassio.cfg
	--mqttjson
	--mqttlog
	--mqttretain
	--mqtttopic=ebusd
	--log=all:notice
	--log=main:notice
	--log=bus:notice
	--log=update:notice
	--log=network:notice
	--log=other:notice"
EOF

motd_ssh
customize
cleanup_lxc
