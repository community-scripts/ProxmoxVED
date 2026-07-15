#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: esatbayhan
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://www.firecrawl.dev/

APP="Firecrawl"
var_tags="${var_tags:-scraping;ai;crawler}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-60}"
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

  if [[ ! -d /opt/firecrawl/apps/api ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "firecrawl" "firecrawl/firecrawl"; then
    msg_info "Stopping Services"
    systemctl stop firecrawl firecrawl-playwright
    msg_ok "Stopped Services"

    create_backup /opt/firecrawl/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "firecrawl" "firecrawl/firecrawl" "tarball" "latest" "/opt/firecrawl"

    restore_backup

    msg_info "Patching Playwright Bind Address"
    if ! grep -q 'app.listen(port, () => {' /opt/firecrawl/apps/playwright-service-ts/api.ts; then
      msg_error "Expected Playwright listen call not found"
      exit 1
    fi
    sed -i 's|app.listen(port, () => {|app.listen(Number(port), "127.0.0.1", () => {|' /opt/firecrawl/apps/playwright-service-ts/api.ts
    msg_ok "Patched Playwright Bind Address"

    msg_info "Building Go Library"
    cd /opt/firecrawl/apps/api/sharedLibs/go-html-to-md
    $STD go mod tidy
    $STD go build -o libhtml-to-markdown.so -buildmode=c-shared html-to-markdown.go
    msg_ok "Built Go Library"

    msg_info "Building Firecrawl API"
    cd /opt/firecrawl/apps/api
    $STD pnpm install --frozen-lockfile
    $STD pnpm build
    CI=true $STD pnpm prune --prod --ignore-scripts
    msg_ok "Built Firecrawl API"

    msg_info "Building Playwright Service"
    cd /opt/firecrawl/apps/playwright-service-ts
    $STD npm install
    $STD npx playwright install chromium --with-deps
    $STD npm run build
    $STD npm prune --omit=dev
    msg_ok "Built Playwright Service"

    msg_info "Starting Services"
    systemctl start firecrawl-playwright firecrawl
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3002${CL}"
echo -e "${INFO}${YW}Configuration file:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/opt/firecrawl/.env${CL}"
