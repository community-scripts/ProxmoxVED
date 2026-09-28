#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: austinpilz
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rhasspy/wyoming-faster-whisper

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y libgomp1
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv

msg_info "Installing Wyoming faster-whisper"
$STD uv venv --python 3.12 /opt/wyoming-faster-whisper
# ctranslate2 and onnxruntime take tens of minutes to build from source, and a
# silent sdist fallback is how this install ends up "working" but unusably slow
$STD uv pip install --python /opt/wyoming-faster-whisper/bin/python \
  --only-binary=ctranslate2,onnxruntime,tokenizers,av,numpy \
  wyoming-faster-whisper
cat <<EOF >~/.wyoming-faster-whisper
$(get_latest_github_release "rhasspy/wyoming-faster-whisper")
EOF
msg_ok "Installed Wyoming faster-whisper"

msg_info "Installing Wyoming Piper"
$STD uv venv --python 3.12 /opt/wyoming-piper
$STD uv pip install --python /opt/wyoming-piper/bin/python \
  --only-binary=piper-tts,onnxruntime,numpy \
  wyoming-piper
cat <<EOF >~/.wyoming-piper
$(get_latest_github_release "OHF-Voice/wyoming-piper")
EOF
msg_ok "Installed Wyoming Piper"

# Both models are fetched now so the first Home Assistant request is not a
# multi-hundred-megabyte cold start
msg_info "Downloading Whisper Model (small-int8)"
mkdir -p /opt/wyoming-voice/whisper
# The rhasspy/faster-whisper-*-int8 repos ship config.json/model.bin/vocabulary.txt
# but no tokenizer.json, so faster-whisper falls back to fetching openai/whisper-tiny's
# tokenizer through the HF_HOME cache, which download_root does not cover. Construct
# the model exactly as the service does so both caches are warm before first boot.
HF_HOME=/opt/wyoming-voice/whisper $STD /opt/wyoming-faster-whisper/bin/python -c \
  "from faster_whisper import WhisperModel; WhisperModel('rhasspy/faster-whisper-small-int8', download_root='/opt/wyoming-voice/whisper', device='cpu', compute_type='default')"
msg_ok "Downloaded Whisper Model (small-int8)"

msg_info "Downloading Piper Voice (en_US-lessac-medium)"
mkdir -p /opt/wyoming-voice/piper
$STD /opt/wyoming-piper/bin/python -m piper.download_voices en_US-lessac-medium --download-dir /opt/wyoming-voice/piper
msg_ok "Downloaded Piper Voice (en_US-lessac-medium)"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/wyoming-faster-whisper.service
[Unit]
Description=Wyoming faster-whisper (speech-to-text)
Documentation=https://github.com/rhasspy/wyoming-faster-whisper
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/wyoming-faster-whisper
Environment=HF_HOME=/opt/wyoming-voice/whisper
ExecStart=/opt/wyoming-faster-whisper/bin/python -m wyoming_faster_whisper \\
  --uri tcp://0.0.0.0:10300 \\
  --data-dir /opt/wyoming-voice/whisper \\
  --model small-int8 \\
  --language en \\
  --beam-size 1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Streaming is on by default in wyoming-piper 2.x; the only related flag is
# --no-streaming, so there is nothing to pass here to enable it
cat <<EOF >/etc/systemd/system/wyoming-piper.service
[Unit]
Description=Wyoming Piper (text-to-speech)
Documentation=https://github.com/OHF-Voice/wyoming-piper
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/wyoming-piper
ExecStart=/opt/wyoming-piper/bin/python -m wyoming_piper \\
  --uri tcp://0.0.0.0:10200 \\
  --data-dir /opt/wyoming-voice/piper \\
  --voice en_US-lessac-medium
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now wyoming-faster-whisper wyoming-piper

# piper-tts ships a single abi3 wheel, so a stable-ABI mismatch surfaces as an
# ImportError at startup rather than as a resolution failure. Waiting for both
# sockets is what proves the two venvs actually run.
READY=0
for _ in {1..30}; do
  if (exec 3<>/dev/tcp/127.0.0.1/10300) 2>/dev/null && (exec 3<>/dev/tcp/127.0.0.1/10200) 2>/dev/null; then
    READY=1
    break
  fi
  sleep 2
done
if [[ "$READY" -ne 1 ]]; then
  msg_error "Wyoming faster-whisper or Wyoming Piper did not start listening within 60 seconds — check 'systemctl status wyoming-faster-whisper wyoming-piper'"
  exit 1
fi
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc
