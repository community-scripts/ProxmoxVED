#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ggml-org/llama.cpp

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Settings the caller may supply up front, declared in json/llama-cpp.json as
# app_vars. Every one of them self-defaults, so passing nothing installs the
# same CPU build as before on a container without a GPU.
var_backend="${var_backend:-auto}"
var_model_repo="${var_model_repo:-ggml-org/gemma-3-1b-it-GGUF}"
var_port="${var_port:-8080}"
var_ctx_size="${var_ctx_size:-4096}"
var_offload_layers="${var_offload_layers:-}"
var_api_key="${var_api_key:-}"

# Which prebuilt upstream ships decides what the container can offload to.
# Upstream has no Linux CUDA build, so Vulkan is the GPU path for NVIDIA too.
if [[ "$var_backend" == "auto" ]]; then
  if [[ -e /dev/kfd ]]; then
    var_backend="rocm"
  elif [[ -e /dev/nvidia0 || -d /dev/dri ]]; then
    var_backend="vulkan"
  else
    var_backend="cpu"
  fi
fi

LLAMA_ARCH="$(arch_resolve x64 arm64)"
if [[ "$LLAMA_ARCH" == "arm64" && "$var_backend" == "rocm" ]]; then
  msg_warn "No arm64 ROCm build is published - falling back to the CPU build"
  var_backend="cpu"
fi

case "$var_backend" in
vulkan) LLAMA_ASSET="llama-*-bin-ubuntu-vulkan-${LLAMA_ARCH}.tar.gz" ;;
rocm) LLAMA_ASSET="llama-*-bin-ubuntu-rocm-*-x64.tar.gz" ;;
*)
  var_backend="cpu"
  LLAMA_ASSET="llama-*-bin-ubuntu-${LLAMA_ARCH}.tar.gz"
  ;;
esac

msg_info "Installing Dependencies"
LLAMA_DEPS=(libgomp1)
[[ "$var_backend" == "vulkan" ]] && LLAMA_DEPS+=(libvulkan1 mesa-vulkan-drivers vulkan-tools)
$STD apt install -y "${LLAMA_DEPS[@]}"
msg_ok "Installed Dependencies"

# Pulls in the userland the vulkan and rocm builds need; a no-op without a GPU.
setup_hwaccel

fetch_and_deploy_gh_release "llama-cpp" "ggml-org/llama.cpp" "prebuild" "latest" "/opt/llama-cpp" "$LLAMA_ASSET"

msg_info "Configuring llama.cpp"
chmod +x /opt/llama-cpp/llama-*
mkdir -p /opt/llama-cpp_data/models
# The update path reads this back: a CPU tarball over a Vulkan install would
# silently drop GPU offload on the next update.
echo "$var_backend" >/opt/llama-cpp_data/.backend
if [[ -z "$var_offload_layers" ]]; then
  [[ "$var_backend" == "cpu" ]] && var_offload_layers=0 || var_offload_layers=999
fi
cat <<EOF >/opt/llama-cpp.env
LLAMA_ARG_HOST=0.0.0.0
LLAMA_ARG_PORT=${var_port}

# Model to serve. Either point at a local GGUF file:
#LLAMA_ARG_MODEL=/opt/llama-cpp_data/models/your-model.gguf
# ...or let llama-server pull one from Hugging Face on first start:
LLAMA_ARG_HF_REPO=${var_model_repo}

LLAMA_CACHE=/opt/llama-cpp_data/models
LLAMA_ARG_CTX_SIZE=${var_ctx_size}
LLAMA_ARG_N_GPU_LAYERS=${var_offload_layers}
EOF
# An empty LLAMA_ARG_API_KEY is not "no key" to llama-server - it demands an
# empty bearer token from every client - so it is left commented out instead.
if [[ -n "$var_api_key" ]]; then
  echo "LLAMA_ARG_API_KEY=${var_api_key}" >>/opt/llama-cpp.env
else
  echo "#LLAMA_ARG_API_KEY=" >>/opt/llama-cpp.env
fi
chmod 600 /opt/llama-cpp.env
msg_ok "Configured llama.cpp (${var_backend} build)"

# A GPU build that cannot see its libraries or its device still starts and then
# runs on the CPU, so say so here rather than let it look like it worked.
if [[ "$var_backend" != "cpu" ]]; then
  if LD_LIBRARY_PATH=/opt/llama-cpp ldd /opt/llama-cpp/llama-server 2>/dev/null | grep -q "not found"; then
    msg_warn "The ${var_backend} build is missing shared libraries in this container - it will fall back to the CPU"
  elif [[ "$var_backend" == "vulkan" ]] && ! vulkaninfo --summary >/dev/null 2>&1; then
    msg_warn "Vulkan build installed but no Vulkan device is visible - check GPU passthrough and the driver libraries in the container"
  fi
fi

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/llama-cpp.service
[Unit]
Description=llama.cpp Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/llama-cpp
EnvironmentFile=/opt/llama-cpp.env
Environment=LD_LIBRARY_PATH=/opt/llama-cpp
ExecStart=/opt/llama-cpp/llama-server
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now llama-cpp
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
