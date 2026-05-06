#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: piotrlaczykowski
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/vllm-project/vllm

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  python3 \
  python3-dev \
  build-essential \
  pkg-config \
  libssl-dev \
  libffi-dev
msg_ok "Installed Dependencies"

setup_hwaccel "vllm"
setup_uv

msg_info "Setting up Python Environment"
$STD uv venv /opt/vllm/.venv
msg_ok "Set up Python Environment"

RELEASE=$(get_latest_github_release "vllm-project/vllm")

msg_info "Installing ${APP} v${RELEASE} (Patience — this takes 5-15 minutes)"
if nvidia-smi &>/dev/null; then
  msg_info "GPU detected — installing vLLM with CUDA support"
  $STD uv pip install --python /opt/vllm/.venv/bin/python "vllm==${RELEASE}"
else
  msg_info "No GPU detected — installing vLLM with CPU/OpenVINO backend"
  $STD uv pip install --python /opt/vllm/.venv/bin/python "vllm==${RELEASE}" --extra-index-url https://download.pytorch.org/whl/cpu
fi
echo "v${RELEASE}" >/opt/vLLM_version.txt
msg_ok "Installed ${APP} v${RELEASE}"

msg_info "Configuring ${APP}"
mkdir -p /etc/vllm /opt/vllm-models
cat <<EOF >/etc/vllm/vllm.env
# Set MODEL to a Hugging Face model ID before starting the service.
# Example (small, ungated): Qwen/Qwen2.5-0.5B-Instruct
# Example (medium):        Qwen/Qwen2.5-7B-Instruct
# Example (gated):         meta-llama/Llama-3.1-8B-Instruct (requires HF_TOKEN)
MODEL="Qwen/Qwen2.5-0.5B-Instruct"
HOST="0.0.0.0"
PORT="8000"
GPU_MEM_UTIL="0.90"
MAX_MODEL_LEN="4096"
TENSOR_PARALLEL_SIZE="1"
QUANTIZATION=""
# HF_TOKEN=""
HF_HOME="/opt/vllm-models"
EOF
msg_ok "Configured ${APP}"

msg_info "Creating vLLM Server Wrapper"
cat <<'EOF' >/usr/local/bin/vllm-server
#!/usr/bin/env bash
set -a
source /etc/vllm/vllm.env
set +a

EXTRA_ARGS=()
[[ -n "${QUANTIZATION}" ]] && EXTRA_ARGS+=(--quantization "${QUANTIZATION}")
[[ -n "${MAX_MODEL_LEN}" && "${MAX_MODEL_LEN}" != "0" ]] && EXTRA_ARGS+=(--max-model-len "${MAX_MODEL_LEN}")
[[ -n "${HF_TOKEN}" ]] && export HUGGING_FACE_HUB_TOKEN="${HF_TOKEN}"

exec /opt/vllm/.venv/bin/python -m vllm.entrypoints.openai.api_server \
  --model "${MODEL}" \
  --host "${HOST}" \
  --port "${PORT}" \
  --gpu-memory-utilization "${GPU_MEM_UTIL}" \
  --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}" \
  --trust-remote-code \
  "${EXTRA_ARGS[@]}"
EOF
chmod +x /usr/local/bin/vllm-server
msg_ok "Created vLLM Server Wrapper"

msg_info "Creating Service"
cat <<'EOF' >/etc/systemd/system/vllm.service
[Unit]
Description=vLLM OpenAI-Compatible Inference Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vllm
ExecStart=/usr/local/bin/vllm-server
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vllm

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q vllm
msg_ok "Created Service (not started — configure /etc/vllm/vllm.env first)"

msg_info "Installing vllm-cli helper"
cat <<'EOF' >/usr/local/bin/vllm-cli
#!/usr/bin/env bash
case "$1" in
  start)
    systemctl start vllm
    echo "vLLM starting... check logs with: journalctl -u vllm -f"
    ;;
  stop) systemctl stop vllm ;;
  restart) systemctl restart vllm ;;
  status) systemctl status vllm ;;
  logs) journalctl -u vllm -f --no-pager ;;
  config) "${EDITOR:-nano}" /etc/vllm/vllm.env ;;
  models)
    /opt/vllm/.venv/bin/python -c "
import os, pathlib
hf_home = os.environ.get('HF_HOME', '/opt/vllm-models')
models = [d for d in pathlib.Path(hf_home).glob('models--*') if d.is_dir()]
if models:
    print('Cached models:')
    for m in models:
        print(' ' + m.name.replace('models--', '').replace('--', '/'))
else:
    print('No cached models found in', hf_home)
"
    ;;
  version)
    /opt/vllm/.venv/bin/python -c "import vllm; print('vLLM', vllm.__version__)"
    ;;
  *) echo "Usage: vllm-cli {start|stop|restart|status|logs|config|models|version}" ;;
esac
EOF
chmod +x /usr/local/bin/vllm-cli
msg_ok "Installed vllm-cli helper"

motd_ssh
customize
cleanup_lxc
