#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: YOUR_GITHUB_USERNAME
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# shellcheck source=/dev/null
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ─── Load config passed by ct script ─────────────────────────────────────────
CONFIG_FILE="/tmp/tm-setup/config.env"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

TM_STORAGE_TYPE="${TM_STORAGE_TYPE:-dir}"
TM_QUOTA="${TM_QUOTA:-1T}"
TM_PASSWORD="${TM_PASSWORD:-}"
TM_NFS_SERVER="${TM_NFS_SERVER:-}"
TM_NFS_SHARE="${TM_NFS_SHARE:-}"
TM_DASHBOARD="${TM_DASHBOARD:-no}"

# ─── Install packages ─────────────────────────────────────────────────────────
msg_info "Installing Samba and Avahi"
$STD apt-get install -y samba avahi-daemon
msg_ok "Installed Samba and Avahi"

# ─── Prepare mount point ─────────────────────────────────────────────────────
msg_info "Preparing storage at /mnt/timemachine"
mkdir -p /mnt/timemachine

case "$TM_STORAGE_TYPE" in
  zfs|dir)
    # ZFS: bind mount already configured by the ct script, just fix perms
    # dir: local directory inside the LXC disk
    ;;

  nfs)
    msg_info "Mounting NFS share ${TM_NFS_SERVER}:${TM_NFS_SHARE}"
    $STD apt-get install -y nfs-common
    echo "${TM_NFS_SERVER}:${TM_NFS_SHARE} /mnt/timemachine nfs defaults,_netdev 0 0" >> /etc/fstab
    $STD mount /mnt/timemachine
    msg_ok "NFS share mounted"
    ;;
esac

# ─── System user ─────────────────────────────────────────────────────────────
msg_info "Creating system user 'timemachine'"
if ! id -u timemachine &>/dev/null; then
  useradd -M -s /sbin/nologin timemachine
fi
chown timemachine:timemachine /mnt/timemachine
chmod 777 /mnt/timemachine
# Subdirectory for Ubuntu/Déjà Dup backups
mkdir -p /mnt/timemachine/ubuntu
chown timemachine:timemachine /mnt/timemachine/ubuntu
msg_ok "User 'timemachine' created"

# ─── Samba password ──────────────────────────────────────────────────────────
if [[ -n "$TM_PASSWORD" ]]; then
  msg_info "Setting Samba password for user 'timemachine'"
  (echo "$TM_PASSWORD"; echo "$TM_PASSWORD") | smbpasswd -a -s timemachine
  SAMBA_SECURITY_BLOCK="   valid users = timemachine"
  SAMBA_GUEST_BLOCK=""
else
  msg_info "Configuring Samba for guest access (no password)"
  SAMBA_SECURITY_BLOCK="   guest ok = yes"
  SAMBA_GUEST_BLOCK="   map to guest = Bad User"
fi
msg_ok "Samba authentication configured"

# ─── Samba configuration ─────────────────────────────────────────────────────
msg_info "Writing Samba configuration"

FORCE_USER_LINE="   force user = timemachine"
[[ -n "$TM_PASSWORD" ]] && FORCE_USER_LINE=""

cat > /etc/samba/smb.conf <<EOF
[global]
   workgroup = WORKGROUP
   server string = Proxmox Time Machine
   server role = standalone server
   log file = /var/log/samba/log.%m
   max log size = 50
   dns proxy = no
${SAMBA_GUEST_BLOCK:+   map to guest = Bad User}
   guest account = nobody
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
${SAMBA_SECURITY_BLOCK}
${FORCE_USER_LINE}
   fruit:time machine = yes
   fruit:time machine max size = ${TM_QUOTA}
   durable handles = yes
   kernel oplocks = no
   kernel share modes = no
   posix locking = no
EOF

msg_ok "Samba configuration written"

# ─── Avahi (mDNS discovery) ───────────────────────────────────────────────────
msg_info "Configuring Avahi for Time Machine discovery"
cat > /etc/avahi/services/timemachine.service <<'EOF'
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
msg_ok "Avahi service configured"

# ─── Enable & start services ─────────────────────────────────────────────────
msg_info "Enabling services"
$STD systemctl enable --now smbd avahi-daemon
msg_ok "Services started (smbd, avahi-daemon)"

# ─── Optional PHP dashboard ───────────────────────────────────────────────────
if [[ "$TM_DASHBOARD" == "yes" ]]; then
  msg_info "Installing PHP dashboard"
  $STD apt-get install -y php-cli

  DASHBOARD_DIR="/var/www/timemachine"
  mkdir -p "$DASHBOARD_DIR"

  # Download dashboard from the community-scripts assets
  curl -fsSL \
    "https://raw.githubusercontent.com/YOUR_USERNAME/ProxmoxVED/main/misc/timemachine-dashboard.php" \
    -o "${DASHBOARD_DIR}/index.php" 2>/dev/null \
    || msg_error "Could not download dashboard — install manually"

  # Systemd service for the PHP built-in server
  cat > /etc/systemd/system/timemachine-dashboard.service <<EOF
[Unit]
Description=Time Machine PHP Dashboard
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:8080 ${DASHBOARD_DIR}/index.php
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  $STD systemctl enable --now timemachine-dashboard
  msg_ok "Dashboard installed and running on port 8080"
fi

# ─── Cleanup ─────────────────────────────────────────────────────────────────
rm -rf /tmp/tm-setup
$STD apt-get -y autoremove
$STD apt-get -y autoclean

# ─── Summary ─────────────────────────────────────────────────────────────────
msg_ok "Samba Time Machine installation complete"
echo ""
echo -e "  ${TAB}${BOLD}${YW}Configuration summary:${CL}"
echo -e "  ${TAB}  Storage backend : ${GN}${TM_STORAGE_TYPE}${CL}"
echo -e "  ${TAB}  Backup path     : ${GN}/mnt/timemachine${CL}"
echo -e "  ${TAB}  Time Machine quota : ${GN}${TM_QUOTA}${CL}"
echo -e "  ${TAB}  Auth            : ${GN}$([ -n "$TM_PASSWORD" ] && echo "password (user: timemachine)" || echo "guest (no password)")${CL}"
echo -e "  ${TAB}  SMB share       : ${GN}smb://$(hostname -I | awk '{print $1}')/TimeMachine${CL}"
[[ "$TM_DASHBOARD" == "yes" ]] && \
  echo -e "  ${TAB}  Dashboard       : ${GN}http://$(hostname -I | awk '{print $1}'):8080${CL}"
echo ""
