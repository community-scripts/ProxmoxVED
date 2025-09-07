#!/usr/bin/env bash
# -----------------------------------------------------------------
# Proxmox Add-IPs (LXC + VMs → Tags)
# -----------------------------------------------------------------
# © 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT
# -----------------------------------------------------------------

APP="Proxmox Add-IPs"
FILE_PATH="/usr/local/bin/prx-add-ips"
CONF_DIR="/opt/prx-add-ips"
CONF_FILE="$CONF_DIR/prx-add-ips.conf"

set -Eeuo pipefail

# --- Farben (optional) ---
YW="\033[33m"
GN="\033[1;92m"
RD="\033[01;31m"
CL="\033[m"
msg() { [[ "${USE_COLOR:-true}" == "true" ]] && echo -e "$@" || echo -e "$(echo "$@" | sed -E 's/\x1B\[[0-9;]*[JKmsu]//g')"; }
msg_info() { msg "${YW}➜ $1${CL}"; }
msg_ok() { msg "${GN}✔ $1${CL}"; }
msg_error() { msg "${RD}✖ $1${CL}"; }

# -----------------------------------------------------------------
# Installation
# -----------------------------------------------------------------
if [[ -f "$FILE_PATH" ]]; then
  msg_info "$APP already installed at $FILE_PATH"
  exit 0
fi

msg_info "Installing dependencies"
apt-get update -qq
apt-get install -y jq ipcalc net-tools >/dev/null
msg_ok "Dependencies installed"

mkdir -p "$CONF_DIR"

# -----------------------------------------------------------------
# Config
# -----------------------------------------------------------------
if [[ ! -f "$CONF_FILE" ]]; then
  cat <<EOF >"$CONF_FILE"
# prx-add-ips.conf – configuration for Proxmox Add-IPs

# Allowed CIDRs
CIDR_LIST=(
  192.168.0.0/16
  10.0.0.0/8
  172.16.0.0/12
)

# Main loop interval in seconds
LOOP_INTERVAL=60

# Use colored output? (true/false)
USE_COLOR=true
EOF
  msg_ok "Default config written to $CONF_FILE"
else
  msg_info "Config $CONF_FILE already exists"
fi

# -----------------------------------------------------------------
# Main Script
# -----------------------------------------------------------------
cat <<"EOF" >"$FILE_PATH"
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="/opt/prx-add-ips/prx-add-ips.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

YW="\033[33m"; GN="\033[1;92m"; RD="\033[01;31m"; CL="\033[m"
msg() { [[ "${USE_COLOR:-true}" == "true" ]] && echo -e "$@" || echo -e "$(echo "$@" | sed -E 's/\x1B\[[0-9;]*[JKmsu]//g')"; }
msg_info() { msg "${YW}➜ $1${CL}"; }
msg_ok()   { msg "${GN}✔ $1${CL}"; }
msg_error(){ msg "${RD}✖ $1${CL}"; }

is_valid_ipv4() {
  local ip=$1
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  for part in ${ip//./ }; do
    ((part >= 0 && part <= 255)) || return 1
  done
  return 0
}

ip_in_cidrs() {
  local ip="$1"
  for cidr in "${CIDR_LIST[@]}"; do
    ipcalc -nb "$cidr" "$ip" &>/dev/null && return 0
  done
  return 1
}

set_tags() {
  local vmid="$1" kind="$2"; shift 2
  local ips=("$@")

  # aktuelle Tags holen
  local existing_tags=()
  mapfile -t existing_tags < <($kind config "$vmid" | awk '/tags:/{$1=""; print}' | tr ';' '\n')

  local existing_ips=()
  local non_ip_tags=()
  for t in "${existing_tags[@]}"; do
    if is_valid_ipv4 "$t"; then
      existing_ips+=("$t")
    else
      non_ip_tags+=("$t")
    fi
  done

  local new_tags=("${non_ip_tags[@]}" "${ips[@]}")
  new_tags=($(printf "%s\n" "${new_tags[@]}" | sort -u))

  if [[ "$(printf "%s\n" "${existing_ips[@]}" | sort -u)" != "$(printf "%s\n" "${ips[@]}" | sort -u)" ]]; then
    msg_info "$kind $vmid → updating tags to ${new_tags[*]}"
    $kind set "$vmid" -tags "$(IFS=';'; echo "${new_tags[*]}")"
  else
    msg_info "$kind $vmid → no IP change"
  fi
}

update_lxc_iptags() {
  for vmid in $(pct list | awk 'NR>1 {print $1}'); do
    local ips=()
    for ip in $(lxc-info -n "$vmid" -iH 2>/dev/null); do
      is_valid_ipv4 "$ip" && ip_in_cidrs "$ip" && ips+=("$ip")
    done
    [[ ${#ips[@]} -gt 0 ]] && set_tags "$vmid" pct "${ips[@]}"
  done
}

update_vm_iptags() {
  for vmid in $(qm list | awk 'NR>1 {print $1}'); do
    if qm agent "$vmid" ping &>/dev/null; then
      local ips=()
      mapfile -t ips < <(qm agent "$vmid" network-get-interfaces \
        | jq -r '.[]?."ip-addresses"[]?."ip-address" | select(test("^[0-9]+\\."))')
      local filtered=()
      for ip in "${ips[@]}"; do
        is_valid_ipv4 "$ip" && ip_in_cidrs "$ip" && filtered+=("$ip")
      done
      [[ ${#filtered[@]} -gt 0 ]] && set_tags "$vmid" qm "${filtered[@]}"
    fi
  done
}

while true; do
  update_lxc_iptags
  update_vm_iptags
  sleep "${LOOP_INTERVAL:-60}"
done
EOF

chmod +x "$FILE_PATH"
msg_ok "Main script installed to $FILE_PATH"

# -----------------------------------------------------------------
# Systemd Service
# -----------------------------------------------------------------
SERVICE="/etc/systemd/system/prx-add-ips.service"
if [[ ! -f "$SERVICE" ]]; then
  cat <<EOF >"$SERVICE"
[Unit]
Description=Proxmox Add-IPs (LXC + VM)
After=network.target

[Service]
Type=simple
ExecStart=$FILE_PATH
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  msg_ok "Service created"
fi

systemctl daemon-reload
systemctl enable -q --now prx-add-ips.service
msg_ok "$APP service started"
