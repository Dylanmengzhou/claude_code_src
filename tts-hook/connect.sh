#!/bin/bash
# 在你自己的电脑(Mac)上执行：打通到 GPU 服务器的隧道。
# 幂等：已有隧道会先清掉再重建。用法：
#   bash tts-hook/connect.sh [ssh别名]     # 默认别名 autodl-vox
set -u
HOST="${1:-autodl-vox}"

# 坑: 本机若自己装了 Ollama，会占住 11434。远端 LLM 一律映射到本地 11435，
# settings-*-tts.json 里的 ANTHROPIC_BASE_URL 也写 11435，两边永不冲突。
pkill -f "ssh.*-N -L 8850:" 2>/dev/null
sleep 1
ssh -f -N \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes \
  -L 8850:127.0.0.1:8850 \
  -L 11435:127.0.0.1:11434 \
  "$HOST" || { echo "隧道建立失败：检查 ssh $HOST 是否免密可登"; exit 1; }

echo -n "TTS  (8850): "
echo '{"cmd":"ping"}' | nc -w 5 127.0.0.1 8850 || echo "无响应（服务器上先跑 server_start.sh）"
echo -n "LLM (11435): "
curl -s --max-time 5 http://127.0.0.1:11435/api/version || echo "无响应（TTS-only 模式可忽略）"
echo
