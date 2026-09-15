#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MrNRod
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Viren070/AIOStreams

APP="AIOStreams"
var_tags="${var_tags:-media;streaming;stremio}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}" # upstream ships official multi-arch (amd64+arm64) images; not independently verified on arm64 hardware by this script's author
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/aiostreams ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "aiostreams" "Viren070/AIOStreams" "" "" "v"; then
    msg_info "Stopping Service"
    systemctl stop aiostreams
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "aiostreams" "Viren070/AIOStreams" "tarball" "latest" "" "" "v"
    AIOSTREAMS_TAG="v$(cat ~/.aiostreams)"

    msg_info "Building Application (Patience)"
    cd /opt/aiostreams
    corepack enable
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    export NODE_OPTIONS="--max-old-space-size=3072"
    $STD pnpm install --frozen-lockfile
    $STD pnpm run build
    unset NODE_OPTIONS
    cp -r /opt/aiostreams/packages/server/src/static /opt/aiostreams/packages/server/dist/static
    msg_ok "Built Application"

    msg_info "Generating Version Metadata"
    ensure_dependencies jq
    mkdir -p /opt/aiostreams/resources
    AIOSTREAMS_VERSION=$(jq -r '.version' /opt/aiostreams/package.json)
    AIOSTREAMS_DESC=$(jq -r '.description' /opt/aiostreams/package.json)
    AIOSTREAMS_COMMIT_INFO=$(curl -fsSL "https://api.github.com/repos/Viren070/AIOStreams/commits/${AIOSTREAMS_TAG}" 2>/dev/null)
    AIOSTREAMS_COMMIT=$(jq -r '.sha // empty' <<<"${AIOSTREAMS_COMMIT_INFO}")
    AIOSTREAMS_COMMIT_TIME=$(jq -r '.commit.committer.date // empty' <<<"${AIOSTREAMS_COMMIT_INFO}")
    [[ -z "${AIOSTREAMS_COMMIT}" ]] && AIOSTREAMS_COMMIT="unknown"
    [[ -z "${AIOSTREAMS_COMMIT_TIME}" || "${AIOSTREAMS_COMMIT_TIME}" == "null" ]] && AIOSTREAMS_COMMIT_TIME=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    cat <<EOF >/opt/aiostreams/resources/metadata.json
{
  "version": "${AIOSTREAMS_VERSION}",
  "description": $(jq -Rn --arg d "${AIOSTREAMS_DESC}" '$d'),
  "tag": "${AIOSTREAMS_TAG}",
  "channel": "stable",
  "commitHash": "${AIOSTREAMS_COMMIT:0:8}",
  "buildTime": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "commitTime": "${AIOSTREAMS_COMMIT_TIME}"
}
EOF
    msg_ok "Generated Version Metadata"

    msg_info "Starting Service"
    systemctl start aiostreams
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW} No authentication is enabled by default.${CL}"
echo -e "${INFO}${YW} Set AIOSTREAMS_AUTH in /opt/aiostreams_data/.env to secure the dashboard.${CL}"
