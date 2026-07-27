#!/bin/bash
# 每次服务器开机后执行一次：启动 TTS（和可选的 LLM）常驻服务。
# 幂等：已在跑的服务不会重复启动。
#   bash server_start.sh            # TTS + LLM
#   bash server_start.sh --tts-only # 只启动 TTS
set -u
export PATH=/root/miniconda3/bin:/usr/local/bin:$PATH
# ollama pull/serve 必须直连，不能带学术加速代理
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY 2>/dev/null || true

TTS_ONLY=0
[ "${1:-}" = "--tts-only" ] && TTS_ONLY=1

# --- VoxCPM TTS (port 8850) ---
if echo '{"cmd":"ping"}' | timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/8850; cat >&3; head -1 <&3' 2>/dev/null | grep -q pong; then
  echo "TTS already up."
else
  tmux kill-session -t vox 2>/dev/null
  fuser -k 8850/tcp 2>/dev/null; sleep 1
  # TORCHDYNAMO_DISABLE=1: 规避 einops/dynamo 编译崩溃
  tmux new-session -d -s vox \
    "cd /root/VoxCPM && TORCHDYNAMO_DISABLE=1 PATH=/root/miniconda3/bin:\$PATH python infer_server.py --port 8850 --model-path ./pretrained_models/VoxCPM2 --device cuda --base-dir . > /root/vox.log 2>&1"
  echo "TTS starting (model loads on first request, ~35s)."
fi

# --- Ollama LLM (port 11434) ---
if [ $TTS_ONLY -eq 0 ]; then
  if curl -s --max-time 3 http://127.0.0.1:11434/api/version >/dev/null; then
    echo "Ollama already up."
  else
    tmux kill-session -t ollama 2>/dev/null
    fuser -k 11434/tcp 2>/dev/null; sleep 1
    tmux new-session -d -s ollama \
      "OLLAMA_MODELS=/root/autodl-tmp/ollama-models OLLAMA_HOST=127.0.0.1:11434 ollama serve > /root/ollama.log 2>&1"
    echo "Ollama starting."
  fi
fi

sleep 3
tmux ls 2>/dev/null
