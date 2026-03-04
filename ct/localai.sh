#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)


# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAI

APP="LocalAI"
var_tags="${var_tags:-ai;llm}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-64}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
color
catch_errors

function amd_gpu_detected() {
  if [[ "${GPU_TYPE:-}" == "AMD" ]]; then
    return 0
  fi
  if ! command -v lspci >/dev/null 2>&1; then
    return 1
  fi
  lspci -nn 2>/dev/null | grep -qE '(VGA|3D controller).*\[(1002|1022):'
}

function ensure_kfd_passthrough() {
  local reboot_mode="${1:-if-changed}"
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
  if [[ "$changed" -ne 0 ]]; then
    msg_ok "Configured /dev/kfd passthrough"
  fi

  if pct status "$CTID" | grep -q "running" && { [[ "$changed" -ne 0 ]] || [[ "$reboot_mode" == "always" ]]; }; then
    msg_info "Restarting container to apply /dev/kfd passthrough"
    pct reboot "$CTID" >/dev/null 2>&1 || {
      pct stop "$CTID"
      pct start "$CTID"
    }
    msg_ok "Restarted container"
  fi

  if pct exec "$CTID" -- test -e /dev/kfd; then
    msg_ok "/dev/kfd is available in container"
    return 0
  fi

  msg_warn "/dev/kfd still missing in container after passthrough configuration"
}

function install_rocm_if_kfd() {
  local container_has_kfd=0
  local want_rocm=0
  if pct exec "$CTID" -- test -e /dev/kfd; then
    container_has_kfd=1
  fi
  if [[ "$container_has_kfd" -eq 1 ]] || [[ "${GPU_TYPE:-}" == "AMD" ]] || amd_gpu_detected; then
    want_rocm=1
  fi

  if [[ "$want_rocm" -ne 1 ]]; then
    msg_warn "Skipping ROCm install: no AMD GPU detected and /dev/kfd not present in container"
    return 0
  fi

  if pct exec "$CTID" -- dpkg -s rocm >/dev/null 2>&1; then
    msg_ok "ROCm already installed"
    if [[ "$container_has_kfd" -ne 1 ]]; then
      msg_warn "ROCm is installed, but /dev/kfd is not present in container yet"
    fi
    return 0
  fi

  msg_info "Installing ROCm"
  pct exec "$CTID" -- bash -lc '
    set -e
    export DEBIAN_FRONTEND=noninteractive

    apt_get_retry_install() {
      local args="$*"
      local attempt
      for attempt in 1 2 3; do
        apt-get -qq -o Dpkg::Use-Pty=0 -o Acquire::Retries=5 -o Acquire::http::No-Cache=true -o Acquire::https::No-Cache=true update >/dev/null 2>&1 && \
          apt-get -qq -o Dpkg::Use-Pty=0 -o Acquire::Retries=5 install -y $args >/dev/null 2>&1 && return 0
        apt-get clean || true
        rm -rf /var/lib/apt/lists/* || true
        if [[ "$attempt" -lt 3 ]]; then
          sleep 5
        fi
      done
      return 1
    }

    apt_get_retry_install --no-install-recommends curl gpg ca-certificates
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

  apt_get_retry_install --fix-missing --no-install-recommends rocm
  '
  msg_ok "Installed ROCm"
  if [[ "$container_has_kfd" -ne 1 ]]; then
    msg_warn "ROCm installed without /dev/kfd; add /dev/kfd passthrough and restart container for GPU acceleration"
  fi
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
  install_rocm_if_kfd

  if check_for_gh_release "localai" "mudler/LocalAI"; then
    msg_info "Stopping LocalAI Service"
    pct exec "$CTID" -- systemctl stop localai || true
    msg_ok "Stopped LocalAI Service"

    fetch_and_deploy_gh_release "localai" "mudler/LocalAI" "singlefile" "latest" "/opt/localai-bin" "local-ai-v*-linux-amd64"

    msg_info "Updating LocalAI Binary"
    pct exec "$CTID" -- bash -lc '
      set -e
      localai_binary="$(find /opt/localai-bin -maxdepth 1 -type f -name "local-ai-v*-linux-amd64" | sort | tail -n1)"
      if [[ -z "$localai_binary" ]]; then
        echo "Unable to locate downloaded LocalAI linux-amd64 binary" >&2
        exit 1
      fi
      install -m 755 "$localai_binary" /usr/local/bin/local-ai
      if [[ -f ~/.localai ]]; then
        tr -d "\n" <~/.localai >/opt/localai_version.txt
      fi
    '
    msg_ok "Updated LocalAI Binary"

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
install_rocm_if_kfd
description
ensure_kfd_passthrough "always"

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
