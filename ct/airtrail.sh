#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Majiiin
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/johanohly/AirTrail

APP="AirTrail"
var_tags="${var_tags:-travel;flight-tracker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/airtrail ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="22" setup_nodejs

  msg_info "Updating Bun"
  export BUN_INSTALL="/root/.bun"
  curl -fsSL https://bun.com/install | $STD bash
  ln -sf /root/.bun/bin/bun /usr/local/bin/bun
  ln -sf /root/.bun/bin/bunx /usr/local/bin/bunx
  msg_ok "Updated Bun"

  if check_for_gh_release "airtrail" "johanohly/AirTrail"; then
    msg_info "Backing Up Database"
    mkdir -p /var/lib/airtrail/backups
    backup_file="/var/lib/airtrail/backups/airtrail-$(date +%Y%m%d-%H%M%S).sql"
    sudo -u postgres pg_dump airtrail | tee "$backup_file" >/dev/null
    find /var/lib/airtrail/backups \
      -type f \
      -name 'airtrail-*.sql' \
      -mtime +14 \
      -delete
    msg_ok "Backed Up Database"

    systemctl stop airtrail

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release \
      "airtrail" \
      "johanohly/AirTrail" \
      "tarball"

    msg_info "Building AirTrail"
    cd /opt/airtrail
    $STD bun install --frozen-lockfile
    $STD bun run build
    rm -rf /opt/airtrail/node_modules
    $STD bun install --frozen-lockfile --production
    msg_ok "Built AirTrail"

    msg_info "Installing Airport Overlay"
    if ! command -v skopeo >/dev/null 2>&1; then
      $STD apt install -y skopeo
    fi

    overlay_tmp=$(mktemp -d)

    overlay_image=$(
      awk '
        $1 == "FROM" &&
        $2 ~ /^johly\/airtrail-airport-overlay(:|@)/ {
          print $2
          exit
        }
      ' /opt/airtrail/docker/Dockerfile
    )

    if [[ -z "$overlay_image" ]]; then
      msg_error "Airport overlay image not found"
      exit 1
    fi

    if [[ "$overlay_image" == *@sha256:* ]]; then
      image_without_digest="${overlay_image%@*}"
      image_digest="${overlay_image#*@}"
      image_repository="${image_without_digest%:*}"
      skopeo_image="${image_repository}@${image_digest}"
    else
      skopeo_image="$overlay_image"
    fi

    mkdir -p \
      "$overlay_tmp/archive" \
      "$overlay_tmp/rootfs"

    $STD skopeo copy \
      "docker://docker.io/${skopeo_image}" \
      "docker-archive:${overlay_tmp}/overlay.tar:airtrail-overlay:latest"

    tar -xf "$overlay_tmp/overlay.tar" \
      -C "$overlay_tmp/archive"

    overlay_layer=$(
      jq -r '.[0].Layers[-1]' \
        "$overlay_tmp/archive/manifest.json"
    )

    tar -xf "$overlay_tmp/archive/$overlay_layer" \
      -C "$overlay_tmp/rootfs"

    if [[ ! -s "$overlay_tmp/rootfs/airport-overlay.pmtiles" ]]; then
      msg_error "Airport overlay file not found"
      exit 1
    fi

    install \
      -o root \
      -g root \
      -m 0644 \
      "$overlay_tmp/rootfs/airport-overlay.pmtiles" \
      /opt/airtrail/build/client/airport-overlay.pmtiles

    rm -rf "$overlay_tmp"
    msg_ok "Installed Airport Overlay"

    msg_info "Applying Database Migrations"
    set -a
    source /etc/airtrail/airtrail.env
    set +a
    $STD node /opt/airtrail/docker/migrate.js
    msg_ok "Applied Database Migrations"

    systemctl start airtrail
    msg_ok "Updated successfully!"
  fi

  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
