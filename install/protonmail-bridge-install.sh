#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Stephen Chin
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ProtonMail/proton-bridge
# Description: Installs Proton Mail Bridge, creates systemd services, and exposes IMAP/SMTP via systemd-socket-proxyd.

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y pass
msg_ok "Installed Dependencies"

msg_info "Creating Service User"
if ! id -u protonbridge >/dev/null 2>&1; then
  useradd -r -m -d /home/protonbridge -s /usr/sbin/nologin protonbridge
fi
install -d -m 0750 -o protonbridge -g protonbridge /home/protonbridge
msg_ok "Created Service User"

msg_info "Installing Proton Mail Bridge"
fetch_and_deploy_gh_release "protonmail-bridge" "ProtonMail/proton-bridge" "binary"
msg_ok "Installed Proton Mail Bridge"

msg_info "Creating Services"

cat <<'EOF'> /etc/systemd/system/protonmail-bridge.service
[Unit]
Description=Proton Mail Bridge (noninteractive)
After=network-online.target
Wants=network-online.target

ConditionPathExists=/home/protonbridge/.protonmailbridge-initialized

[Service]
Type=simple
User=protonbridge
Group=protonbridge
WorkingDirectory=/home/protonbridge
Environment=HOME=/home/protonbridge

ExecStart=/usr/bin/protonmail-bridge --noninteractive

Restart=always
RestartSec=3

NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes

[Install]
WantedBy=multi-user.target
EOF

# IMAP socket (LAN 143)
cat > /etc/systemd/system/protonmail-bridge-imap.socket <<'EOF'
[Unit]
Description=Proton Mail Bridge IMAP Socket (143)
ConditionPathExists=/home/protonbridge/.protonmailbridge-initialized

[Socket]
ListenStream=143
Accept=no
Service=protonmail-bridge-imap-proxy.service

[Install]
WantedBy=sockets.target
EOF

# IMAP proxy service (143 -> 127.0.0.1:1143)
cat <<'EOF'>/etc/systemd/system/protonmail-bridge-imap-proxy.service
[Unit]
Description=Proton Mail Bridge IMAP Proxy (143 -> 127.0.0.1:1143)
After=protonmail-bridge.service
Requires=protonmail-bridge.service
ConditionPathExists=/home/protonbridge/.protonmailbridge-initialized

[Service]
Type=simple
Sockets=protonmail-bridge-imap.socket
ExecStart=/usr/lib/systemd/systemd-socket-proxyd 127.0.0.1:1143
NoNewPrivileges=yes
PrivateTmp=yes
EOF

# SMTP socket (LAN 587)
cat > /etc/systemd/system/protonmail-bridge-smtp.socket <<'EOF'
[Unit]
Description=Proton Mail Bridge SMTP Socket (587)
ConditionPathExists=/home/protonbridge/.protonmailbridge-initialized

[Socket]
ListenStream=587
Accept=no
Service=protonmail-bridge-smtp-proxy.service

[Install]
WantedBy=sockets.target
EOF

# SMTP proxy service (587 -> 127.0.0.1:1025)
cat <<'EOF'>/etc/systemd/system/protonmail-bridge-smtp-proxy.service
[Unit]
Description=Proton Mail Bridge SMTP Proxy (587 -> 127.0.0.1:1025)
After=protonmail-bridge.service
Requires=protonmail-bridge.service
ConditionPathExists=/home/protonbridge/.protonmailbridge-initialized

[Service]
Type=simple
Sockets=protonmail-bridge-smtp.socket
ExecStart=/usr/lib/systemd/systemd-socket-proxyd 127.0.0.1:1025
NoNewPrivileges=yes
PrivateTmp=yes
EOF

systemctl daemon-reload
msg_ok "Created Services"

msg_info "Creating Helper Commands"

cat > /usr/local/bin/protonmailbridge-init <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BRIDGE_USER="protonbridge"
BRIDGE_HOME="/home/${BRIDGE_USER}"
MARKER="${BRIDGE_HOME}/.protonmailbridge-initialized"

if [[ -f "$MARKER" ]]; then
  echo "Already initialized."
  echo "To start services:"
  echo "  systemctl enable --now protonmail-bridge.service"
  echo "  systemctl enable --now protonmail-bridge-imap.socket protonmail-bridge-smtp.socket"
  exit 0
fi

# Stop sockets/proxies/bridge daemon if they were manually started
systemctl stop protonmail-bridge-imap.socket protonmail-bridge-smtp.socket 2>/dev/null || true
systemctl stop protonmail-bridge-imap-proxy.service protonmail-bridge-smtp-proxy.service protonmail-bridge.service 2>/dev/null || true

echo "Initializing pass keychain for ${BRIDGE_USER} (required by Proton Mail Bridge on Linux)."

install -d -m 0700 -o "${BRIDGE_USER}" -g "${BRIDGE_USER}" "${BRIDGE_HOME}/.gnupg"

FPR="$(runuser -u "${BRIDGE_USER}" -- env HOME="${BRIDGE_HOME}" GNUPGHOME="${BRIDGE_HOME}/.gnupg" \
  gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')"

if [[ -z "${FPR}" ]]; then
  runuser -u "${BRIDGE_USER}" -- env HOME="${BRIDGE_HOME}" GNUPGHOME="${BRIDGE_HOME}/.gnupg" \
    gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-gen-key 'ProtonMail Bridge' default default never

  FPR="$(runuser -u "${BRIDGE_USER}" -- env HOME="${BRIDGE_HOME}" GNUPGHOME="${BRIDGE_HOME}/.gnupg" \
    gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')"
fi

if [[ -z "${FPR}" ]]; then
  echo "Failed to detect a GPG key fingerprint for ${BRIDGE_USER}." >&2
  exit 1
fi

runuser -u "${BRIDGE_USER}" -- env HOME="${BRIDGE_HOME}" GNUPGHOME="${BRIDGE_HOME}/.gnupg" \
  pass init "${FPR}"

echo
echo "Starting Proton Mail Bridge CLI for one-time login."
echo "Run: login"
echo "Run: info"
echo "Run: exit"
echo

runuser -u "${BRIDGE_USER}" -- env HOME="${BRIDGE_HOME}" \
  protonmail-bridge -c

touch "${MARKER}"
chown "${BRIDGE_USER}:${BRIDGE_USER}" "${MARKER}"
chmod 0644 "${MARKER}"

systemctl daemon-reload
systemctl enable -q --now protonmail-bridge.service
systemctl enable -q --now protonmail-bridge-imap.socket protonmail-bridge-smtp.socket

echo "Initialization complete. Services enabled and started."
EOF
chmod +x /usr/local/bin/protonmailbridge-init
ln -sf /usr/local/bin/protonmailbridge-init /usr/bin/protonmailbridge-init

cat > /usr/local/bin/protonmailbridge-configure <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BRIDGE_USER="protonbridge"
BRIDGE_HOME="/home/${BRIDGE_USER}"
MARKER="${BRIDGE_HOME}/.protonmailbridge-initialized"

if [[ ! -f "${MARKER}" ]]; then
  echo "Not initialized yet. Run:"
  echo "  protonmailbridge-init"
  exit 1
fi

systemctl stop protonmail-bridge-imap.socket protonmail-bridge-smtp.socket 2>/dev/null || true
systemctl stop protonmail-bridge-imap-proxy.service protonmail-bridge-smtp-proxy.service protonmail-bridge.service 2>/dev/null || true

runuser -u "${BRIDGE_USER}" -- env HOME="${BRIDGE_HOME}" \
  protonmail-bridge -c

systemctl daemon-reload
systemctl enable -q --now protonmail-bridge.service
systemctl enable -q --now protonmail-bridge-imap.socket protonmail-bridge-smtp.socket
EOF
chmod +x /usr/local/bin/protonmailbridge-configure
ln -sf /usr/local/bin/protonmailbridge-configure /usr/bin/protonmailbridge-configure

msg_ok "Created Helper Commands"

motd_ssh
customize
cleanup_lxc
