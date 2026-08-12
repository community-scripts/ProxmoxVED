#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ggml-org/llama.cpp

APP="llama-cpp"
var_tags="${var_tags:-ai;llm}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_gpu="${var_gpu:-yes}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/llama-cpp ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "llama-cpp" "ggml-org/llama.cpp"; then
    msg_info "Stopping Service"
    systemctl stop llama-cpp
    msg_ok "Stopped Service"

    # Keep the build variant the install picked; the CPU tarball would otherwise
    # overwrite a Vulkan or ROCm install and quietly end GPU offload.
    LLAMA_BACKEND="$(cat /opt/llama-cpp_data/.backend 2>/dev/null || echo cpu)"
    case "$LLAMA_BACKEND" in
    vulkan) LLAMA_ASSET="llama-*-bin-ubuntu-vulkan-$(arch_resolve x64 arm64).tar.gz" ;;
    rocm) LLAMA_ASSET="llama-*-bin-ubuntu-rocm-*-x64.tar.gz" ;;
    *) LLAMA_ASSET="llama-*-bin-ubuntu-$(arch_resolve x64 arm64).tar.gz" ;;
    esac

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "llama-cpp" "ggml-org/llama.cpp" "prebuild" "latest" "/opt/llama-cpp" "$LLAMA_ASSET"
    chmod +x /opt/llama-cpp/llama-*

    msg_info "Starting Service"
    systemctl start llama-cpp
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
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW}Change the served model in /opt/llama-cpp.env${CL}"
