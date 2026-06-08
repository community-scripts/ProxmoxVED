#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: armm29393
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/3proxy/3proxy

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y openssl ca-certificates
msg_ok "Installed Dependencies"

msg_info "Installing 3proxy (GitHub release)"

RELEASE=$(get_latest_github_release "3proxy/3proxy")
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64) DEB_FILE="3proxy-${RELEASE}.x86_64.deb" ;;
  arm64) DEB_FILE="3proxy-${RELEASE}.arm64.deb" ;;
  armhf) DEB_FILE="3proxy-${RELEASE}.arm.deb"   ;;
  *)
    msg_error "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

DEB_URL="https://github.com/3proxy/3proxy/releases/download/${RELEASE}/${DEB_FILE}"
curl -fsSL -o /tmp/3proxy.deb "$DEB_URL"
$STD dpkg -i /tmp/3proxy.deb
rm -f /tmp/3proxy.deb
msg_ok "Installed 3proxy ${RELEASE}"

msg_info "Generating Proxy Credentials"

PROXY_USER=$(prompt_input "Proxy username" "proxyuser" 30)
PROXY_PASS=$(prompt_password "Proxy password" "generate" 30 8)
PROXY_PASS_HASH=$(/usr/bin/mycrypt 12345 "$PROXY_PASS")
PROXY_PASS_HASH="${PROXY_PASS_HASH#CR:}"

cat > /root/3proxy.creds <<CREDSEOF
# 3proxy Credentials
# Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
# IP: ${IP:-<container-ip>}
# Username: ${PROXY_USER}
# Password: ${PROXY_PASS}
# Hash (CR): ${PROXY_PASS_HASH}
CREDSEOF
chmod 600 /root/3proxy.creds
msg_ok "Generated Proxy Credentials (saved to /root/3proxy.creds)"

msg_info "Writing /etc/3proxy/3proxy.cfg"

mkdir -p /etc/3proxy/conf
printf 'users %s:CR:%s\n' "$PROXY_USER" "$PROXY_PASS_HASH" > /etc/3proxy/conf/passwd
chmod 600 /etc/3proxy/conf/passwd

cat > /etc/3proxy/3proxy.cfg <<CFGEOF
daemon
pidfile /run/3proxy/3proxy.pid
nserver 1.1.1.1
nserver 8.8.8.8
nscache 65536

flush
auth strong
users \$/etc/3proxy/conf/passwd
allow ${PROXY_USER}
proxy -p${PROXY_HTTP_PORT:-3128} -n
socks -p${PROXY_SOCKS_PORT:-1080}
socks -p${PROXY_SOCKS4_PORT:-1081} -4
flush

flush
auth strong
users \$/etc/3proxy/conf/passwd
allow ${PROXY_USER}
pop3p -p${PROXY_POP3_PORT:-1100}
smtpp -p${PROXY_SMTP_PORT:-8025}
ftppr -p${PROXY_FTP_PORT:-2121}
flush
CFGEOF

chmod 644 /etc/3proxy/3proxy.cfg
msg_ok "Wrote /etc/3proxy/3proxy.cfg"

mkdir -p /var/log/3proxy
chown proxy:proxy /var/log/3proxy
chmod 0755 /var/log/3proxy

msg_info "Enabling 3proxy Service"
systemctl enable -q --now 3proxy
msg_ok "3proxy Service Started"

motd_ssh
customize
cleanup_lxc
