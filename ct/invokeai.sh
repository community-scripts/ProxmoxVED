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
var_disk="${var_disk:-60}"
var_gpu="${var_gpu:-yes}"

if [[ -z "${var_torch_backend:-}" && "${var_gpu:-no}" == "yes" ]]; then
  if [[ -e /dev/nvidia0 || -e /dev/nvidiactl ]] || lspci 2>/dev/null | grep -qi 'NVIDIA'; then
    var_torch_backend="cu128"
  elif [[ -e /dev/kfd ]] || lspci 2>/dev/null | grep -qiE 'AMD|Radeon'; then
    var_torch_backend="rocm7.2"
  fi
fi

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
    INVOKEAI_CONFIG="/opt/invokeai/root/invokeai.yaml"
    if [[ -f "${INVOKEAI_CONFIG}" ]] && ! grep -qE '^[[:space:]]*schema_version:' "${INVOKEAI_CONFIG}"; then
      msg_warn "Detected invalid invokeai.yaml (missing schema_version)"
      mv "${INVOKEAI_CONFIG}" "${INVOKEAI_CONFIG}.broken.$(date +%s)"
      msg_ok "Backed up invalid invokeai.yaml; InvokeAI will regenerate defaults"
    fi

    if grep -qE -- '--host|--port' /etc/systemd/system/invokeai.service || ! grep -q '^Environment=INVOKEAI_HOST=0.0.0.0' /etc/systemd/system/invokeai.service || ! grep -q '^Environment=LD_LIBRARY_PATH=' /etc/systemd/system/invokeai.service; then
      msg_info "Repairing InvokeAI Service"
      cat <<EOF >/etc/systemd/system/invokeai.service
[Unit]
Description=InvokeAI Web Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/invokeai
Environment=INVOKEAI_HOST=0.0.0.0
Environment=INVOKEAI_PORT=9090
Environment=LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib64:/usr/lib:/usr/lib64
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
        elif grep -qEi '0x1002|0x1022' /sys/class/drm/renderD*/device/vendor /sys/class/drm/card*/device/vendor 2>/dev/null; then
          TORCH_BACKEND="rocm7.2"
        fi
      fi
      ;;
    esac

    if [[ "${var_gpu:-no}" == "yes" && "${TORCH_BACKEND}" == "cpu" && -e /dev/kfd ]]; then
      TORCH_BACKEND="rocm7.2"
    fi

    ROCM72_INDEX_URL="https://download.pytorch.org/whl/test/rocm7.2"

    install_rocm72_wheels() {
      msg_info "Installing ROCm 7.2 PyTorch packages from PyTorch test index"
      $STD uv pip install --python /opt/invokeai/.venv/bin/python --upgrade \
        torch torchvision torchaudio triton \
        --index-url "${ROCM72_INDEX_URL}"
      msg_ok "Installed ROCm 7.2 PyTorch packages"
    }

    install_rocm_runtime_debian() {
      retry_cmd() {
        local max_attempts="$1"
        local base_delay="$2"
        shift 2
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
          if "$@"; then
            return 0
          fi
          if [[ $attempt -lt $max_attempts ]]; then
            msg_warn "Command failed (attempt ${attempt}/${max_attempts}): $*"
            sleep $((base_delay * attempt))
          fi
          attempt=$((attempt + 1))
        done
        return 1
      }

      fetch_rocm_key() {
        curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg
      }

      run_rocm_apt_update() {
        $STD apt update
      }

      run_rocm_apt_install_full() {
        $STD apt install -y rocm
      }

      if [[ -f /etc/os-release ]]; then
        . /etc/os-release
      fi

      local rocm_suite=""
      case "${VERSION_ID:-}" in
      13*) rocm_suite="noble" ;;
      12*) rocm_suite="jammy" ;;
      *)
        msg_warn "Unsupported Debian version for automatic ROCm repo setup"
        return 1
        ;;
      esac

      msg_info "Installing ROCm runtime packages (${rocm_suite})"
      mkdir -p /etc/apt/keyrings
      if ! retry_cmd 3 5 fetch_rocm_key; then
        msg_warn "Failed to add ROCm apt signing key"
        return 1
      fi

      cat <<EOF >/etc/apt/sources.list.d/rocm.list
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 ${rocm_suite} main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2/ubuntu ${rocm_suite} main
EOF

      cat <<EOF >/etc/apt/preferences.d/rocm-pin-600
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

      msg_info "Updating apt repositories for ROCm"
      if ! retry_cmd 3 5 run_rocm_apt_update; then
        msg_warn "ROCm apt repository update failed"
        return 1
      fi

      msg_info "Installing ROCm runtime apt packages"
      if ! retry_cmd 3 10 run_rocm_apt_install_full; then
        msg_warn "ROCm runtime package installation failed"
        return 1
      fi

      ldconfig || true
      msg_ok "Installed ROCm runtime packages"
      return 0
    }

    repair_rocm_runtime_libs() {
      local roctx_candidate=""
      if ldconfig -p 2>/dev/null | grep -q 'libroctx64\.so\.4'; then
        msg_ok "Detected libroctx64.so.4 in linker cache"
        return 0
      fi

      roctx_candidate="$(ldconfig -p 2>/dev/null | awk '/libroctx64\.so(\.[0-9]+)?/ && first=="" {first=$NF} END{if(first!="") print first}')"
      if [[ -z "${roctx_candidate}" ]]; then
        roctx_candidate="$(find /opt/rocm /usr/lib /usr/local/lib \( -type f -o -type l \) -name 'libroctx64.so*' 2>/dev/null | head -n1)"
      fi

      if [[ -n "${roctx_candidate}" ]]; then
        local roctx_dir
        roctx_dir="$(dirname "${roctx_candidate}")"
        if [[ ! -e "${roctx_dir}/libroctx64.so.4" ]]; then
          ln -sf "$(basename "${roctx_candidate}")" "${roctx_dir}/libroctx64.so.4" || true
          ldconfig || true
        fi
      fi

      local roctx_files
      roctx_files="$(find /opt/rocm/lib /opt/rocm/lib64 /usr/lib /usr/local/lib \( -type f -o -type l \) -name 'libroctx64.so*' 2>/dev/null | paste -sd ' ' - || true)"
      if [[ -n "${roctx_files}" ]]; then
        msg_info "ROCm libraries found: ${roctx_files}"
      else
        msg_warn "No libroctx64.so* files found under /opt/rocm or standard lib paths"
      fi
    }

    rocm_runtime_available() {
      if ldconfig -p 2>/dev/null | grep -q 'libroctx64\.so\.4'; then
        return 0
      fi
      if [[ -e /opt/rocm/lib/libroctx64.so.4 || -e /opt/rocm/lib/libroctx64.so || -e /opt/rocm/lib64/libroctx64.so.4 || -e /opt/rocm/lib64/libroctx64.so ]]; then
        return 0
      fi
      if find /opt/rocm /usr/lib /usr/local/lib \( -type f -o -type l \) -name 'libroctx64.so*' 2>/dev/null | grep -q .; then
        return 0
      fi
      return 1
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
      install_rocm_runtime_debian || true
      if ! install_rocm72_wheels; then
        systemctl start invokeai || true
        msg_error "Failed to install ROCm 7.2 wheels"
        exit 1
      fi
      msg_info "Installing InvokeAI package (ROCm path, this can take several minutes)"
      if ! $STD uv pip install --python /opt/invokeai/.venv/bin/python --upgrade invokeai; then
        systemctl start invokeai || true
        msg_error "Failed to update InvokeAI"
        exit 1
      fi
      repair_rocm_runtime_libs
      if ! rocm_runtime_available; then
        msg_warn "ROCm runtime libraries are unavailable; switching to CPU backend"
        TORCH_BACKEND="cpu"
        if ! $STD uv pip install --python /opt/invokeai/.venv/bin/python --torch-backend=cpu --upgrade invokeai; then
          systemctl start invokeai || true
          msg_error "Failed to switch to CPU backend"
          exit 1
        fi
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
