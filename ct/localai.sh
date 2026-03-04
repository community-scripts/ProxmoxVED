#!/usr/bin/env bash
export COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/BillyOutlast/ProxmoxVED/LocalAI}"
source <(curl -fsSL https://raw.githubusercontent.com/BillyOutlast/ProxmoxVED/LocalAI/misc/build.func)


# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAI

APP="LocalAI"
var_tags="${var_tags:-ai;llm}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
color
catch_errors

KFD_PASSTHROUGH_ADDED=0

function ensure_kfd_passthrough() {
  if ! command -v lspci >/dev/null 2>&1; then
    return 0
  fi
  if ! lspci -nn 2>/dev/null | grep -qE '\[1002:|\[1022:'; then
    return 0
  fi
  if [[ ! -e /dev/kfd ]]; then
    msg_warn "AMD GPU detected but /dev/kfd is missing on host"
    return 0
  fi

  local lxc_config="/etc/pve/lxc/${CTID}.conf"
  if [[ ! -f "$lxc_config" ]]; then
    return 0
  fi
  if grep -qE '^dev[0-9]+:\s*/dev/kfd' "$lxc_config"; then
    return 0
  fi

  local next_dev
  next_dev="$(grep -oE '^dev[0-9]+:' "$lxc_config" | sed -E 's/^dev([0-9]+):$/\1/' | sort -n | tail -n1)"
  if [[ -z "$next_dev" ]]; then
    next_dev=0
  else
    next_dev=$((next_dev + 1))
  fi

  msg_info "Configuring /dev/kfd passthrough"
  echo "dev${next_dev}: /dev/kfd,gid=44" >>"$lxc_config"
  echo "lxc.cgroup2.devices.allow: c 235:* rwm" >>"$lxc_config"
  KFD_PASSTHROUGH_ADDED=1
  msg_ok "Configured /dev/kfd passthrough"

  if pct status "$CTID" | grep -q "running"; then
    msg_info "Restarting container to apply /dev/kfd passthrough"
    pct reboot "$CTID" >/dev/null 2>&1 || {
      pct stop "$CTID"
      pct start "$CTID"
    }
    msg_ok "Restarted container"
  fi
}

function install_rocm_if_kfd() {
  if [[ "$KFD_PASSTHROUGH_ADDED" != "1" ]]; then
    return 0
  fi

  msg_info "Installing ROCm after /dev/kfd passthrough"
  pct exec "$CTID" -- bash -lc '
    set -e
    if ! test -e /dev/kfd; then
      exit 0
    fi
    if command -v rocminfo >/dev/null 2>&1; then
      exit 0
    fi

    apt-get update -y
    apt-get install -y curl gpg ca-certificates
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg
    chmod 644 /etc/apt/keyrings/rocm.gpg

    cat <<EOF >/etc/apt/sources.list.d/rocm.list
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2/ubuntu noble main
EOF

    cat <<EOF >/etc/apt/preferences.d/rocm-pin-600
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

    apt-get update -y
    apt-get install -y rocm
  '
  msg_ok "Installed ROCm"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/pve/lxc/${CTID}.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  if ! pct exec "$CTID" -- test -x /usr/local/bin/local-ai; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  ensure_kfd_passthrough

  if check_for_gh_release "localai" "mudler/LocalAI"; then
    msg_info "Stopping LocalAI Service"
    pct exec "$CTID" -- systemctl stop localai || true
    msg_ok "Stopped LocalAI Service"

    msg_info "Updating LocalAI"
    pct exec "$CTID" -- bash -lc '
      set -e
      release_json="$(curl -fsSL https://api.github.com/repos/mudler/LocalAI/releases/latest)"
      release_tag="$(echo "$release_json" | jq -r '.tag_name')"
      asset_url="$(echo "$release_json" | jq -r '\'' .assets[] | select(.name | test("^local-ai-v.*-linux-amd64$")) | .browser_download_url '\'' | head -n1)"
      if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
        echo "Unable to resolve LocalAI linux-amd64 release asset" >&2
        exit 1
      fi
      curl -fsSL "$asset_url" -o /usr/local/bin/local-ai
      chmod 755 /usr/local/bin/local-ai
      if [[ -n "$release_tag" && "$release_tag" != "null" ]]; then
        echo "${release_tag#v}" >/opt/localai_version.txt
      fi
    '
    msg_ok "Updated LocalAI"

    msg_info "Starting LocalAI Service"
    pct exec "$CTID" -- systemctl restart localai || {
      msg_error "Failed to start LocalAI service"
      exit 1
    }
    msg_ok "Started LocalAI Service"

    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
ensure_kfd_passthrough
install_rocm_if_kfd
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"

if [[ -z "${IP:-}" ]]; then
  IP=$(pct exec "$CTID" -- sh -c "hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | head -n1")
fi
if [[ -z "${IP:-}" ]]; then
  IP=$(pct exec "$CTID" -- sh -c "hostname -I 2>/dev/null | tr ' ' '\n' | grep -E ':' | head -n1")
fi

URL_HOST="${IP:-}"
if [[ -n "${URL_HOST}" && "${URL_HOST}" == *:* ]]; then
  URL_HOST="[${URL_HOST}]"
fi
if [[ -z "${URL_HOST}" ]]; then
  echo -e "${TAB}${GATEWAY}${BGN}http://<container-ip>:8080${CL}"
else
  echo -e "${TAB}${GATEWAY}${BGN}http://${URL_HOST}:8080${CL}"
fi
