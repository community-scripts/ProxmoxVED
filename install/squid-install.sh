#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: 007hacky007
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.squid-cache.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y squid apache2-utils
msg_ok "Installed Dependencies"

msg_info "Configuring Squid"
rm -f /etc/squid/conf.d/*
cat <<EOF >/etc/squid/squid.conf
acl localnet src 0.0.0.1-0.255.255.255
acl localnet src 10.0.0.0/8
acl localnet src 100.64.0.0/10
acl localnet src 169.254.0.0/16
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10

acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777
acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic realm proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

http_port 3128

coredump_dir /var/spool/squid

refresh_pattern ^ftp:        1440    20%    10080
refresh_pattern ^gopher:     1440    0%     1440
refresh_pattern -i (/cgi-bin/|\\?) 0  0%     0
refresh_pattern .            0       20%    4320

# Privacy / hardening
httpd_suppress_version_string on
visible_hostname $(hostname)
forwarded_for delete
request_header_access X-Forwarded-For deny all
EOF
msg_ok "Configured Squid"

msg_info "Generating Proxy Credentials"
SQUID_USER="proxy"
SQUID_PASS="$(dd if=/dev/urandom bs=32 count=1 status=none | base64 | tr -dc 'A-Za-z0-9' | cut -c1-16)"
$STD htpasswd -cb /etc/squid/passwords "$SQUID_USER" "$SQUID_PASS"
cat <<EOF >/root/squid.creds
Proxy endpoint: $(hostname -I | awk '{print $1}'):3128
Proxy type: HTTP Forward Proxy
Username: ${SQUID_USER}
Password: ${SQUID_PASS}
EOF
chmod 600 /root/squid.creds
msg_ok "Generated Proxy Credentials"
msg_ok "Username: ${SQUID_USER}"
msg_ok "Password: ${SQUID_PASS}"

msg_info "Validating Squid Configuration"
$STD squid -k parse
msg_ok "Validated Squid Configuration"

msg_info "Starting Service"
systemctl enable -q squid
systemctl restart squid
msg_ok "Started Service"

motd_ssh
cat <<EOF >>/etc/profile.d/00_lxc-details.sh
echo ""
echo -e "${BOLD}  Squid Proxy${CL}"
echo -e "    Type: ${GN}HTTP Forward Proxy${CL}"
echo -e "    Port: ${GN}3128${CL}"
echo -e "    Default user: ${GN}${SQUID_USER}${CL}"
echo -e "    Initial password: ${GN}${SQUID_PASS}${CL}"
echo ""
echo -e "${BOLD}  Manage users:${CL}"
echo -e "    Reset password:  ${GN}htpasswd /etc/squid/passwords proxy${CL}"
echo -e "    Add user:        ${GN}htpasswd /etc/squid/passwords <username>${CL}"
echo -e "    Remove user:     ${GN}htpasswd -D /etc/squid/passwords <username>${CL}"
EOF

customize
cleanup_lxc
