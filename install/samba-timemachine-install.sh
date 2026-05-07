#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: sebmoute
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.samba.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  samba \
  avahi-daemon
msg_ok "Installed Dependencies"

msg_info "Configuring Samba Time Machine"
TM_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
useradd -M -s /sbin/nologin timemachine
echo -e "${TM_PASS}\n${TM_PASS}" | smbpasswd -a -s timemachine
mkdir -p /mnt/timemachine
chown timemachine:timemachine /mnt/timemachine
chmod 770 /mnt/timemachine
cat <<EOF >/etc/samba/smb.conf
[global]
   workgroup = WORKGROUP
   server string = Proxmox Time Machine
   server role = standalone server
   log file = /var/log/samba/log.%m
   max log size = 50
   fruit:metadata = stream
   fruit:model = MacSamba
   fruit:posix_rename = yes
   fruit:veto_appledouble = no
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes
   vfs objects = catia fruit streams_xattr

[TimeMachine]
   path = /mnt/timemachine
   browseable = yes
   writable = yes
   valid users = timemachine
   fruit:time machine = yes
   durable handles = yes
   kernel oplocks = no
   kernel share modes = no
   posix locking = no
EOF
mkdir -p /opt/samba-timemachine
cat <<EOF >/opt/samba-timemachine/.env
SAMBA_USER=timemachine
SAMBA_PASS=${TM_PASS}
SHARE_PATH=/mnt/timemachine
EOF
msg_ok "Configured Samba Time Machine"

msg_info "Configuring Avahi"
cat <<EOF >/etc/avahi/services/timemachine.service
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h Time Machine</name>
  <service>
    <type>_adisk._tcp</type>
    <txt-record>sys=waMa=0,adVF=0x100</txt-record>
    <txt-record>dk0=adVF=0xa1,adVN=TimeMachine</txt-record>
  </service>
  <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=TimeCapsule8,119</txt-record>
  </service>
</service-group>
EOF
msg_ok "Configured Avahi"

msg_info "Creating Services"
systemctl enable -q --now smbd
systemctl enable -q --now avahi-daemon
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
