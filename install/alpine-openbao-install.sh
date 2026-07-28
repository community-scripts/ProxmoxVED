#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Marc Went (Dunky13)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://openbao.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apk add --no-cache openssl
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "openbao" "openbao/openbao" "prebuild" "latest" "/opt/openbao" "openbao_*_linux_$(arch_resolve).tar.gz"
ln -sf /opt/openbao/bao /usr/local/bin/bao

msg_info "Generating Self-Signed Certificate"
mkdir -p /etc/openbao/tls /var/lib/openbao
$STD openssl req -out /etc/openbao/tls/tls.crt -new -keyout /etc/openbao/tls/tls.key \
  -newkey rsa:4096 -nodes -sha256 -x509 -subj "/O=OpenBao/CN=OpenBao" -days 1095
chmod 700 /etc/openbao/tls
chmod 600 /etc/openbao/tls/tls.crt /etc/openbao/tls/tls.key
msg_ok "Generated Self-Signed Certificate"

msg_info "Configuring OpenBao"
cat <<EOF >/etc/openbao/openbao.hcl
ui = true

storage "file" {
  path = "/var/lib/openbao"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/openbao/tls/tls.crt"
  tls_key_file  = "/etc/openbao/tls/tls.key"
}
EOF
cat <<EOF >/etc/conf.d/openbao
export BAO_ADDR=https://127.0.0.1:8200
export BAO_SKIP_VERIFY=true
EOF
chmod 600 /etc/conf.d/openbao
cat <<EOF >/etc/profile.d/openbao.sh
export BAO_ADDR=https://127.0.0.1:8200
export BAO_SKIP_VERIFY=true
EOF
source /etc/profile.d/openbao.sh
msg_ok "Configured OpenBao"

msg_info "Creating Service"
cat <<'EOF' >/etc/init.d/openbao
#!/sbin/openrc-run
name="OpenBao"
description="OpenBao - a tool for managing secrets"

command="/opt/openbao/bao"
command_args="server -config=/etc/openbao/openbao.hcl"
supervisor=supervise-daemon
output_log="/var/log/openbao.log"
error_log="/var/log/openbao.log"
respawn_delay=10
rc_cgroup_settings="memory.swap.max 0"

depend() {
  need net
  after firewall
}

start_pre() {
  checkpath -f -m 0640 "$output_log"
}

start_post() {
  [ -n "$BAO_UNSEAL_KEY" ] || return 0
  local i=0
  while [ "$i" -lt 30 ]; do
    curl -fsSk -o /dev/null "$BAO_ADDR/v1/sys/seal-status" && break
    sleep 1
    i=$((i + 1))
  done
  "$command" operator unseal "$BAO_UNSEAL_KEY" >/dev/null 2>&1 || true
}
EOF
chmod +x /etc/init.d/openbao
$STD rc-update add openbao default
$STD rc-service openbao start
for _ in $(seq 1 30); do
  curl -fsSk -o /dev/null "https://127.0.0.1:8200/v1/sys/seal-status" && break
  sleep 2
done
if ! curl -fsSk -o /dev/null "https://127.0.0.1:8200/v1/sys/seal-status"; then
  msg_error "OpenBao did not become ready within 60 seconds"
  exit 1
fi
msg_ok "Created Service"

msg_info "Initializing OpenBao"
(
  umask 077
  cat <<'EOF' >/etc/openbao/openbao-init.json
EOF
)
if ! bao operator init -key-shares=1 -key-threshold=1 -format=json >/etc/openbao/openbao-init.json; then
  msg_error "Failed to initialize OpenBao"
  exit 1
fi
if ! jq -e '(.unseal_keys_b64[0] | type == "string" and length > 0) and (.root_token | type == "string" and length > 0)' /etc/openbao/openbao-init.json >/dev/null; then
  msg_error "OpenBao initialization output is invalid or missing credentials"
  exit 1
fi
cat <<EOF >>/etc/conf.d/openbao
BAO_UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' /etc/openbao/openbao-init.json)
BAO_ROOT_TOKEN=$(jq -r '.root_token' /etc/openbao/openbao-init.json)
EOF
rm -f /etc/openbao/openbao-init.json
$STD rc-service openbao restart
for _ in $(seq 1 15); do
  bao status -format=json 2>/dev/null | jq -e '.sealed == false' >/dev/null && break
  sleep 2
done
if ! bao status -format=json 2>/dev/null | jq -e '.sealed == false' >/dev/null; then
  msg_error "OpenBao did not unseal within 30 seconds"
  exit 1
fi
msg_ok "Initialized OpenBao"

motd_ssh
customize
cleanup_lxc
