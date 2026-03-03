#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/invoke-ai/InvokeAI

APP="InvokeAI"
var_tags="${var_tags:-ai;image-generation}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/invokeai.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "invokeai" "invoke-ai/InvokeAI"; then
    if grep -qE -- '--host|--port' /etc/systemd/system/invokeai.service; then
      msg_info "Repairing InvokeAI Service"
      cat <<EOF >/etc/systemd/system/invokeai.service
[Unit]
Description=InvokeAI Web Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/invokeai
ExecStart=/opt/invokeai/.venv/bin/invokeai-web --root /opt/invokeai/root
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      msg_ok "Repaired InvokeAI Service"
    fi

    TORCH_BACKEND="cpu"
    case "${var_torch_backend:-}" in
    cpu | cu128 | rocm7.2)
      TORCH_BACKEND="${var_torch_backend}"
      ;;
    *)
      if [[ "${var_gpu:-no}" == "yes" ]]; then
        if [[ -e /dev/nvidia0 || -e /dev/nvidiactl ]]; then
          TORCH_BACKEND="cu128"
        elif lspci 2>/dev/null | grep -qiE 'AMD|Radeon'; then
          TORCH_BACKEND="rocm7.2"
        fi
      fi
      ;;
    esac

    ROCM72_TORCH_WHL="https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/torch-2.9.1%2Brocm7.2.0.lw.git7e1940d4-cp312-cp312-linux_x86_64.whl"
    ROCM72_TORCHVISION_WHL="https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/torchvision-0.24.0%2Brocm7.2.0.gitb919bd0c-cp312-cp312-linux_x86_64.whl"
    ROCM72_TRITON_WHL="https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/triton-3.5.1%2Brocm7.2.0.gita272dfa8-cp312-cp312-linux_x86_64.whl"
    ROCM72_TORCHAUDIO_WHL="https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/torchaudio-2.9.0%2Brocm7.2.0.gite3c6ee2b-cp312-cp312-linux_x86_64.whl"

    install_rocm72_wheels() {
      msg_info "Installing ROCm 7.2 PyTorch wheels"
      $STD uv pip uninstall --python /opt/invokeai/.venv/bin/python -y torch torchvision triton torchaudio || true
      $STD uv pip install --python /opt/invokeai/.venv/bin/python \
        "${ROCM72_TORCH_WHL}" \
        "${ROCM72_TORCHVISION_WHL}" \
        "${ROCM72_TORCHAUDIO_WHL}" \
        "${ROCM72_TRITON_WHL}"
      msg_ok "Installed ROCm 7.2 wheels"
    }

    install_cu128_pytorch() {
      msg_info "Installing NVIDIA CUDA 12.8 PyTorch packages"
      $STD uv pip install --python /opt/invokeai/.venv/bin/python torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
      msg_ok "Installed NVIDIA CUDA 12.8 PyTorch packages"
    }

    msg_info "Stopping Service"
    systemctl stop invokeai
    msg_ok "Stopped Service"

    msg_info "Updating InvokeAI (${TORCH_BACKEND})"
    if [[ "${TORCH_BACKEND}" == "rocm7.2" ]]; then
      if ! $STD uv pip install --python /opt/invokeai/.venv/bin/python --upgrade invokeai; then
        systemctl start invokeai || true
        msg_error "Failed to update InvokeAI"
        exit 1
      fi
      if ! install_rocm72_wheels; then
        systemctl start invokeai || true
        msg_error "Failed to install ROCm 7.2 wheels"
        exit 1
      fi
    elif [[ "${TORCH_BACKEND}" == "cu128" ]]; then
      if ! $STD uv pip install --python /opt/invokeai/.venv/bin/python --upgrade invokeai; then
        systemctl start invokeai || true
        msg_error "Failed to update InvokeAI"
        exit 1
      fi
      if ! install_cu128_pytorch; then
        systemctl start invokeai || true
        msg_error "Failed to install NVIDIA CUDA 12.8 PyTorch packages"
        exit 1
      fi
    elif ! $STD uv pip install --python /opt/invokeai/.venv/bin/python --torch-backend="${TORCH_BACKEND}" --upgrade invokeai; then
      systemctl start invokeai || true
      msg_error "Failed to update InvokeAI"
      exit 1
    fi
    msg_ok "Updated InvokeAI"

    msg_info "Starting Service"
    if ! systemctl start invokeai; then
      msg_error "Failed to start InvokeAI"
      exit 1
    fi
    msg_ok "Started Service"

    if ! systemctl is-active -q invokeai; then
      msg_error "InvokeAI service is not running"
      exit 1
    fi

    msg_info "Detecting Runtime Backend"
    RUNTIME_BACKEND="$(/opt/invokeai/.venv/bin/python -c "import torch; import sys; backend='cpu';
if hasattr(torch, 'cuda') and torch.cuda.is_available():
    backend='cuda'
elif getattr(torch.version, 'hip', None):
    backend='rocm'
sys.stdout.write(backend)" 2>/dev/null || true)"
    if [[ -n "${RUNTIME_BACKEND}" ]]; then
      msg_ok "Runtime Backend: ${RUNTIME_BACKEND}"
    else
      msg_warn "Runtime backend could not be detected"
    fi

    INVOKEAI_VERSION="$(/opt/invokeai/.venv/bin/python -c "import importlib.metadata as m; print(m.version('invokeai'))")"
    echo "${INVOKEAI_VERSION}" >"$HOME/.invokeai"
    msg_ok "Updated successfully to v${INVOKEAI_VERSION}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9090${CL}"
