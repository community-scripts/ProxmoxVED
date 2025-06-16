#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://opencloud.eu

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

read -r -p "Enter the hostname of your OpenCloud server: " oc_host
if [[ "$oc_host" ]]; then
  OC_HOST="$oc_host"
fi
read -r -p "Enter the hostname of your Collabora server: " collabora_host
if [[ "$collabora_host" ]]; then
  COLLABORA_HOST="$collabora_host"
fi
read -r -p "Enter the hostname of your WOPI server: " wopi_host
if [[ "$wopi_host" ]]; then
  WOPI_HOST="$wopi_host"
fi

msg_info "Installing Collabora Online"
curl -fsSL https://collaboraoffice.com/downloads/gpg/collaboraonline-release-keyring.gpg -o /etc/apt/keyrings/collaboraonline-release-keyring.gpg

cat <<EOF >/etc/apt/sources.list.d/collaboraonline.sources
Types: deb
URIs: https://www.collaboraoffice.com/repos/CollaboraOnline/CODE-deb
Suites: ./
Signed-By: /etc/apt/keyrings/collaboraonline-release-keyring.gpg
EOF

$STD apt-get update
$STD apt-get install -y coolwsd code-brand
systemctl stop coolwsd
COOLPASS="$(openssl rand -base64 36)"
$STD sudo -u cool coolconfig set-admin-password --user=admin --password="$COOLPASS"
msg_ok "Installed Collabora Online"

msg_info "Installing ${APPLICATION}"
OPENCLOUD=$(curl -s https://api.github.com/repos/opencloud-eu/opencloud/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
DATA_DIR="/var/lib/opencloud/"
CONFIG_DIR="/etc/opencloud"
ENV_FILE="${CONFIG_DIR}/opencloud.env"
curl -fsSL "https://github.com/opencloud-eu/opencloud/releases/download/v${OPENCLOUD}/opencloud-${OPENCLOUD}-linux-amd64" -o /usr/bin/opencloud
chmod +x /usr/bin/opencloud
mkdir -p "$DATA_DIR" "$CONFIG_DIR"/assets/apps
echo "${OPENCLOUD}" >/etc/opencloud/version
msg_ok "Installed ${APPLICATION}"

msg_info "Configuring ${APPLICATION}"
curl -fsSL https://raw.githubusercontent.com/opencloud-eu/opencloud-compose/refs/heads/main/config/opencloud/csp.yaml -o "$CONFIG_DIR"/csp.yaml
curl -fsSL https://github.com/opencloud-eu/opencloud/raw/refs/heads/main/deployments/examples/opencloud_full/config/opencloud/proxy.yaml -o "$CONFIG_DIR"/proxy.yaml.bak

cat <<EOF >"$ENV_FILE"
OC_URL=https://${OC_HOST}
OC_INSECURE=false
IDM_CREATE_DEMO_USERS=false
OC_LOG_LEVEL=warning
OC_CONFIG_DIR=${CONFIG_DIR}
OC_BASE_DATA_PATH=${DATA_DIR}
# Uncomment below when configuring external auth solution (LDAP/OAUTH etc)
# OC_EXCLUDE_RUN_SERVICES=ldm,ldp

# Proxy
# PROXY_ENABLE_BASIC_AUTH=true
PROXY_TLS=false
PROXY_CSP_CONFIG_FILE_LOCATION=${CONFIG_DIR}/csp.yaml

# Collaboration - requires VALID TLS
COLLABORA_DOMAIN=${COLLABORA_HOST}
COLLABORATION_APP_NAME="CollaboraOnline"
COLLABORATION_APP_PRODUCT="Collabora"
COLLABORATION_APP_ADDR=https://${COLLABORA_HOST}
COLLABORATION_APP_INSECURE=false
COLLABORATION_HTTP_ADDR=0.0.0.0:9300
COLLABORATION_WOPI_SRC=https://${WOPI_HOST}
COLLABORATION_JWT_SECRET=

# Applications
WEB_ASSET_APPS_PATH=${CONFIG_DIR}/assets/apps

# Notifications - Email settings
# NOTIFICATIONS_SMTP_HOST=
# NOTIFICATIONS_SMTP_PORT=
# NOTIFICATIONS_SMTP_SENDER=
# NOTIFICATIONS_SMTP_USERNAME=
# NOTIFICATIONS_SMTP_PASSWORD=
# NOTIFICATIONS_SMTP_AUTHENTICATION=login
# Encryption method. Possible values are 'starttls', 'ssltls' and 'none'
# NOTIFICATIONS_SMTP_ENCRYPTION=starttls
# Allow insecure connections. Defaults to false.
# NOTIFICATIONS_SMTP_INSECURE=false

# Start additional services at runtime
# Examples: notifications, antivirus etc.
# Do not uncomment unless configured above.
# OC_ADD_RUN_SERVICES="notifications"
EOF

cat <<EOF >/etc/systemd/system/opencloud.service
[Unit]
Description=OpenCloud server
After=network-online.target

[Service]
Type=simple
User=opencloud
Group=opencloud
EnvironmentFile=${ENV_FILE}
ExecStart=/usr/bin/opencloud server
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/opencloud-wopi.service
[Unit]
Description=OpenCloud WOPI Server
Requires=coolwsd.service
After=network.target opencloud.service coolwsd.service

[Service]
Type=simple
User=opencloud
Group=opencloud
EnvironmentFile=${ENV_FILE}
ExecStart=/usr/bin/opencloud collaboration server
Restart=always
KillSignal=SIGKILL
KillMode=mixed
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF

$STD sudo -u cool coolconfig set ssl.enable false
$STD sudo -u cool coolconfig set ssl.termination true
$STD sudo -u cool coolconfig set ssl.ssl_verification true
sed -i "s|CSP2\"/>|CSP2\">frame-ancestors https://${OC_HOST}</content_security_policy>|" /etc/coolwsd/coolwsd.xml
useradd -r -M -s /usr/sbin/nologin opencloud
chown -R opencloud:opencloud "$CONFIG_DIR" "$DATA_DIR"
sudo -u opencloud opencloud init --config-path "$CONFIG_DIR" --insecure no
OPENCLOUD_SECRET="$(sed -n '/jwt/p' "$CONFIG_DIR"/opencloud.yaml | awk '{print $2}')"
sed -i "s/JWT_SECRET=/&${OPENCLOUD_SECRET}/" "$ENV_FILE"
systemctl enable -q --now coolwsd opencloud opencloud-wopi
msg_ok "Configured ${APPLICATION}"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
