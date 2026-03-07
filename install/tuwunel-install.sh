#!/usr/bin/env bash

# Copyright (c) 2021-2026 tteck
# Author: Dan Erickson (derickson2402)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://matrix-construct.github.io/tuwunel/

# Required by Community-Scripts framework
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Collect server configuration from user
whiptail --title "Attention!" --msgbox "These options cannot be easily changed! Please read the docs before proceeding." 8 60 3>&1 1>&2 2>&3
TUWUNEL_CONF_SERVER_NAME=$(whiptail --title "Server name" --inputbox "Matrix server name, where 'myuser@server-name' will be your public username. Ex: 'example.com'" 8 60 3>&1 1>&2 2>&3)
TUWUNEL_CONF_TUWUNEL_HOST=$(whiptail --title "Tuwunel hostname" --inputbox "Tuwunel's FQDN, where Tuwunel will be accessed. Ex: 'matrix.example.com'" 8 60 3>&1 1>&2 2>&3)

# Tuwunel distributes seperate binaries depending on the encryption hardware
# available in the CPU. As of January 2026, binaries are provided for v1,v2, and
# v3. Use the highest version supported by your CPU. If CPU supports higher (ex.
# v4), use v3. Their docs provide a helpful script to automate this. See:
# https://matrix-construct.github.io/tuwunel/deploying/generic.html#static-prebuilt-binary
msg_info "Identifying CPU architecture and capabilities"
tuwunel_sys_arch=$(dpkg --print-architecture)
case "$tuwunel_sys_arch" in
  amd64) tuwunel_arch_tag="x86_64"
    tuwunel_cpu_caps=$(cat /proc/cpuinfo | \
      grep -Po '(avx|sse)[235]' | sort -u | \
      sed 's/avx5/v4/;s/avx2/v3/;s/sse3/v2/;s/sse2/v1/' | \
      sort -V | tail -n1)
    if [[ "$tuwunel_cpu_caps" =~ ^v[0-9]+$ ]] && (( ${tuwunel_cpu_caps#v} > 3 )); then
      # Binaries only go up to v3. More capable CPU's still use this verison
      tuwunel_cpu_caps="v3"
    fi
    if [[ ! "$tuwunel_cpu_caps" =~ ^v[1-3]$ ]]; then
      msg_error "Could not detect valid CPU feature level. Expected [v1, v3], got $tuwunel_cpu_caps"
      exit 1
    fi
    ;;
  arm64) tuwunel_arch_tag="aarch64"
    # For some reason, ARM CPU's only use v8. Likely because the oldest ARM
    # chips are much newer than older x86 chips
    tuwunel_cpu_caps="v8"
    ;;
  *) msg_error "Unsupported architecture: $tuwunel_sys_arch"; exit 1 ;;
esac
msg_ok "Identified ${tuwunel_arch_tag} CPU with ${tuwunel_cpu_caps} capabilities"

# Download and install Tuwunel debian package for this system. Nice and simple,
# thanks Tuwunel!
msg_info "Updating system packages"
$STD apt update -y
$STD apt upgrade -y
msg_info "Checking GitHub for latest version"
tuwunel_version=$(curl -fsSL https://api.github.com/repos/matrix-construct/tuwunel/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
msg_info "Downloading and installing Tuwunel v${tuwunel_version}"
tuwunel_deb_url="https://github.com/matrix-construct/tuwunel/releases/download/v${tuwunel_version}/v${tuwunel_version}-release-all-${tuwunel_arch_tag}-${tuwunel_cpu_caps}-linux-gnu-tuwunel.deb"
tuwunel_deb_path="/tmp/tuwunel.deb"
curl -fsSL -o "${tuwunel_deb_path}" "${tuwunel_deb_url}"
$STD dpkg -i "${tuwunel_deb_path}"
rm -f "${tuwunel_deb_path}"
echo "${tuwunel_version}" > "/opt/Tuwunel_version.txt"
echo "${tuwunel_arch_tag}" > "/opt/Tuwunel_arch.txt"
echo "${tuwunel_cpu_caps}" > "/opt/Tuwunel_cpu_cap.txt"
msg_ok "Installed Tuwunel v${tuwunel_version}"

# Configure Tuwunel now that it is installed. Debian package creates some of
# this by default, but we explicitly create it here to ensure it is correct and
# permissions are set properly
msg_info "Configuring Tuwunel"
if ! id tuwunel &>/dev/null; then
  # If the deb package already made the user, this safely skips recreating it
  sudo adduser --system tuwunel --group --disabled-login --no-create-home
fi
tuwunel_config_path="/etc/tuwunel/tuwunel.toml"
tuwunel_reg_token_path="/etc/tuwunel/.reg_token"
cp "${tuwunel_config_path}" /etc/tuwunel/tuwunel-example.toml
  cat <<EOF >"${tuwunel_config_path}"
[global]
# Stop! This cannot be changed without a DB wipe! See the docs for details:
#   https://matrix-construct.github.io/tuwunel/configuration/examples.html?highlight=wipe#example-configuration
server_name = "${TUWUNEL_CONF_SERVER_NAME}"

# You can safely leave everything below this line as defaults unless you have
# specific needs to change them.
address = "0.0.0.0"
allow_registration = true
registration_token_file = "${tuwunel_reg_token_path}"

[global.well_known]
client = "https://${TUWUNEL_CONF_TUWUNEL_HOST}"
server = "${TUWUNEL_CONF_TUWUNEL_HOST}:443"
EOF
reg_token=$(openssl rand -base64 200 | tr -dc 'a-zA-Z0-9' | head -c32)
echo "$reg_token" > "${tuwunel_reg_token_path}"
chown -R tuwunel:tuwunel /etc/tuwunel
chmod 755 /etc/tuwunel
chmod 700 "${tuwunel_reg_token_path}"
msg_ok "Configured Tuwunel"

# This is the last prompt the user will see after installation is done, so we
# need to alert them about post-installation setup tasks.
msg_info "Finishing up and starting server"
systemctl enable -q --now tuwunel
msg_warn ""
msg_warn "Tuwunel is serving well-known json for federation at:"
msg_warn "    http://localhost:8008/.well-known/matrix"
msg_warn "Tuwunel is serving matrix federation port at:"
msg_warn "    http://localhost:8448"
msg_warn ""
msg_warn "Tuwunel expects to be proxied to:"
msg_warn "    https://${TUWUNEL_CONF_TUWUNEL_HOST}"
msg_warn "Other users look for you (federation) at either address (pick one):"
msg_warn "    https://$TUWUNEL_CONF_SERVER_NAME/.well-known/matrix"
msg_warn "    $TUWUNEL_CONF_SERVER_NAME:8448"
msg_warn ""
msg_warn "First registered user gets admin rights. Use the token to register:"
msg_warn "    $reg_token"
msg_warn ""
msg_ok "Installation successful!"

# Required by Community-Scripts framework
motd_ssh
customize
cleanup_lxc
