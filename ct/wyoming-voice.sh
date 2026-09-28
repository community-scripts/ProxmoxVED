#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: austinpilz
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rhasspy/wyoming-faster-whisper

APP="Wyoming Voice"
var_tags="${var_tags:-smarthome;voice;stt;tts}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/wyoming-faster-whisper || ! -d /opt/wyoming-piper ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "wyoming-faster-whisper" "rhasspy/wyoming-faster-whisper"; then
    msg_info "Stopping Wyoming faster-whisper"
    systemctl stop wyoming-faster-whisper
    msg_ok "Stopped Wyoming faster-whisper"

    msg_info "Updating Wyoming faster-whisper"
    $STD uv pip install --python /opt/wyoming-faster-whisper/bin/python --upgrade \
      --only-binary=ctranslate2,onnxruntime,tokenizers,av,numpy \
      wyoming-faster-whisper
    msg_ok "Updated Wyoming faster-whisper"

    msg_info "Starting Wyoming faster-whisper"
    systemctl start wyoming-faster-whisper
    msg_ok "Started Wyoming faster-whisper"
  fi

  if check_for_gh_release "wyoming-piper" "OHF-Voice/wyoming-piper"; then
    msg_info "Stopping Wyoming Piper"
    systemctl stop wyoming-piper
    msg_ok "Stopped Wyoming Piper"

    msg_info "Updating Wyoming Piper"
    $STD uv pip install --python /opt/wyoming-piper/bin/python --upgrade \
      --only-binary=piper-tts,onnxruntime,numpy \
      wyoming-piper
    msg_ok "Updated Wyoming Piper"

    msg_info "Starting Wyoming Piper"
    systemctl start wyoming-piper
    msg_ok "Started Wyoming Piper"
  fi

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Add these as Wyoming Protocol integrations in Home Assistant:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Speech-to-Text (faster-whisper): ${IP}:10300${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Text-to-Speech (Piper): ${IP}:10200${CL}"
