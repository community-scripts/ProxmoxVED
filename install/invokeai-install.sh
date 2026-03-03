#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/invoke-ai/InvokeAI

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

INSTALL_DIR="/opt/invokeai"
INVOKEAI_ROOT="${INSTALL_DIR}/root"

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  git \
  libgl1 \
  libglib2.0-0 \
  ffmpeg
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv

msg_info "Installing InvokeAI"
mkdir -p "${INSTALL_DIR}" "${INVOKEAI_ROOT}"
cd "${INSTALL_DIR}" || exit
$STD uv venv --python 3.12 .venv
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
    elif grep -qEi '0x1002|0x1022' /sys/class/drm/renderD*/device/vendor /sys/class/drm/card*/device/vendor 2>/dev/null; then
      TORCH_BACKEND="rocm7.2"
    fi
  fi
  ;;
esac

if [[ "${var_gpu:-no}" == "yes" && "${TORCH_BACKEND}" == "cpu" && -e /dev/kfd ]]; then
  TORCH_BACKEND="rocm7.2"
fi

ROCM72_TORCH_WHL="https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/torch-2.9.1%2Brocm7.2.0.lw.git7e1940d4-cp312-cp312-linux_x86_64.whl"
ROCM72_TORCHVISION_WHL="https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/torchvision-0.24.0%2Brocm7.2.0.gitb919bd0c-cp312-cp312-linux_x86_64.whl"
ROCM72_TRITON_WHL="https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/triton-3.5.1%2Brocm7.2.0.gita272dfa8-cp312-cp312-linux_x86_64.whl"
ROCM72_TORCHAUDIO_WHL="https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/torchaudio-2.9.0%2Brocm7.2.0.gite3c6ee2b-cp312-cp312-linux_x86_64.whl"

install_rocm72_wheels() {
  msg_info "Installing ROCm 7.2 PyTorch wheels"
  $STD uv pip uninstall --python .venv/bin/python -y torch torchvision triton torchaudio || true
  $STD uv pip install --python .venv/bin/python \
    "${ROCM72_TORCH_WHL}" \
    "${ROCM72_TORCHVISION_WHL}" \
    "${ROCM72_TORCHAUDIO_WHL}" \
    "${ROCM72_TRITON_WHL}"
  msg_ok "Installed ROCm 7.2 wheels"
}

install_cu128_pytorch() {
  msg_info "Installing NVIDIA CUDA 12.8 PyTorch packages"
  $STD uv pip install --python .venv/bin/python torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
  msg_ok "Installed NVIDIA CUDA 12.8 PyTorch packages"
}

msg_info "Using torch backend: ${TORCH_BACKEND}"
if [[ "${TORCH_BACKEND}" == "rocm7.2" ]]; then
  $STD uv pip install --python .venv/bin/python --upgrade invokeai
  install_rocm72_wheels
elif [[ "${TORCH_BACKEND}" == "cu128" ]]; then
  $STD uv pip install --python .venv/bin/python --upgrade invokeai
  install_cu128_pytorch
else
  $STD uv pip install --python .venv/bin/python --torch-backend="${TORCH_BACKEND}" --upgrade invokeai
fi
INVOKEAI_VERSION="$(.venv/bin/python -c "import importlib.metadata as m; print(m.version('invokeai'))")"
echo "${INVOKEAI_VERSION}" >"$HOME/.invokeai"
msg_ok "Installed InvokeAI v${INVOKEAI_VERSION}"

INVOKEAI_CONFIG="${INVOKEAI_ROOT}/invokeai.yaml"
if [[ -f "${INVOKEAI_CONFIG}" ]] && ! grep -qE '^[[:space:]]*schema_version:' "${INVOKEAI_CONFIG}"; then
  msg_warn "Detected invalid invokeai.yaml (missing schema_version)"
  mv "${INVOKEAI_CONFIG}" "${INVOKEAI_CONFIG}.broken.$(date +%s)"
  msg_ok "Backed up invalid invokeai.yaml; InvokeAI will regenerate defaults"
fi

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/invokeai.service
[Unit]
Description=InvokeAI Web Service
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
Environment=INVOKEAI_HOST=0.0.0.0
Environment=INVOKEAI_PORT=9090
ExecStart=${INSTALL_DIR}/.venv/bin/invokeai-web --root ${INVOKEAI_ROOT}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now invokeai
msg_ok "Created Service"

msg_info "Detecting Runtime Backend"
RUNTIME_BACKEND="$(${INSTALL_DIR}/.venv/bin/python -c "import torch; import sys; backend='cpu';
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

motd_ssh
customize
cleanup_lxc
