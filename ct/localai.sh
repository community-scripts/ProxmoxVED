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

function ensure_kfd_passthrough() {
  if [[ "${var_gpu:-yes}" != "yes" ]]; then
    return 0
  fi
  if [[ ! -e /dev/kfd ]]; then
    msg_warn "Skipping /dev/kfd passthrough: /dev/kfd is missing on host"
    return 0
  fi

  local lxc_config="/etc/pve/lxc/${CTID}.conf"
  if [[ ! -f "$lxc_config" ]]; then
    return 0
  fi

  local changed=0
  if ! grep -qE '^lxc\.mount\.entry:\s*/dev/kfd\s+dev/kfd\s+none\s+bind,optional,create=file' "$lxc_config"; then
    msg_info "Configuring /dev/kfd mount entry"
    echo "lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file" >>"$lxc_config"
    changed=1
  fi
  if ! grep -qE '^lxc\.cgroup2\.devices\.allow:\s*c\s+235:\*\s+rwm' "$lxc_config"; then
    msg_info "Configuring /dev/kfd cgroup permissions"
    echo "lxc.cgroup2.devices.allow: c 235:* rwm" >>"$lxc_config"
    changed=1
  fi
  if [[ "$changed" -eq 0 ]]; then
    return 0
  fi
  msg_ok "Configured /dev/kfd passthrough"

  if pct status "$CTID" | grep -q "running"; then
    msg_info "Restarting container to apply /dev/kfd passthrough"
    pct reboot "$CTID" >/dev/null 2>&1 || {
      pct stop "$CTID"
      pct start "$CTID"
    }
    msg_ok "Restarted container"
  fi

  if pct exec "$CTID" -- test -e /dev/kfd; then
    msg_ok "/dev/kfd is available in container"
  else
    msg_warn "/dev/kfd still missing in container after passthrough configuration"
  fi
}

function install_rocm_if_kfd() {
  if ! pct exec "$CTID" -- test -e /dev/kfd; then
    msg_warn "Skipping ROCm install: /dev/kfd not present in container"
    return 0
  fi

  if pct exec "$CTID" -- dpkg -s rocm >/dev/null 2>&1; then
    msg_ok "ROCm already installed"
    return 0
  fi

  msg_info "Installing ROCm"
  pct exec "$CTID" -- bash -lc '
    set -e
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
