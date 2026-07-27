#!/bin/bash
# ============================================================================
# AutoDL 一键部署：VoxCPM 语音克隆 (TTS) + Ollama 大模型 (LLM)
#
# 用法（在服务器上执行，建议放 tmux 里跑）：
#   bash server_setup.sh            # 完整安装（TTS + LLM）
#   bash server_setup.sh --tts-only # 只装语音部分（显存小的机器推荐）
#
# 特性：幂等（重复执行只补缺失部分）、断点续传、所有已知坑都已修复。
# 日志: /root/setup.log
# ============================================================================
set -uo pipefail
exec > >(tee -a /root/setup.log) 2>&1

DATA=/root/autodl-tmp                  # AutoDL 数据盘：关机不丢，重置系统也保留
PY=/root/miniconda3/bin/python
PIP=/root/miniconda3/bin/pip
export PATH=/root/miniconda3/bin:/usr/local/bin:$PATH
TTS_ONLY=0
[ "${1:-}" = "--tts-only" ] && TTS_ONLY=1

step() { echo; echo "=== $* ==="; }
die()  { echo "FATAL: $*" >&2; exit 1; }

# 坑1: AutoDL 学术加速只对 github/huggingface 有效，且会拖慢甚至弄坏其他源
# （ollama registry 走它会失败）。策略：HF/GitHub 下载前开启，其余时候关闭。
turbo_on()  { source /etc/network_turbo >/dev/null 2>&1 || true; }
turbo_off() { unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY 2>/dev/null || true; }

step "[0] 基础工具"
command -v tmux  >/dev/null || apt-get install -y -qq tmux  >/dev/null 2>&1 || { apt-get update -qq; apt-get install -y -qq tmux; }
command -v fuser >/dev/null || apt-get install -y -qq psmisc >/dev/null 2>&1
command -v zstd  >/dev/null || apt-get install -y -qq zstd   >/dev/null 2>&1

step "[1] 代码"
turbo_on
cd /root
[ -d VoxCPM ] || git clone https://github.com/Dylanmengzhou/VoxCPM.git \
  || git clone https://gh-proxy.com/https://github.com/Dylanmengzhou/VoxCPM.git \
  || die "VoxCPM clone 失败"

step "[2] Python 环境"
cd /root/VoxCPM
$PIP install -q -e . || die "voxcpm 安装失败"
# 坑2: pip 解析可能装上与 torch 主版本不匹配的 torchaudio（libcudart 报错）。
# 以 torch 实际版本为准对齐 torchaudio。
TORCH_VER=$($PY - <<'EOF'
import torch, re
m = re.match(r'(\d+\.\d+\.\d+)\+(cu\d+)', torch.__version__)
print(m.group(1), m.group(2)) if m else print(torch.__version__, "")
EOF
)
read -r TV CU <<< "$TORCH_VER"
if ! $PY -c "import torchaudio" 2>/dev/null; then
  if [ -n "$CU" ]; then
    $PIP install -q "torchaudio==$TV" --index-url "https://download.pytorch.org/whl/$CU"
  else
    $PIP install -q "torchaudio==$TV"
  fi
fi
# 坑3: 旧版 einops 在新 torch dynamo 下崩溃（运行时再用 TORCHDYNAMO_DISABLE=1 双保险）
$PIP install -q -U einops soundfile "huggingface_hub[cli]"
$PY -c "import voxcpm" || die "voxcpm import 失败"

step "[3] VoxCPM2 权重 (~4.6G, 存数据盘)"
mkdir -p $DATA/models
if [ ! -f $DATA/models/VoxCPM2/model.safetensors ]; then
  # 坑4: huggingface-cli 已废弃，用 hf；失败自动切国内镜像
  hf download openbmb/VoxCPM2 --local-dir $DATA/models/VoxCPM2 \
    || HF_ENDPOINT=https://hf-mirror.com hf download openbmb/VoxCPM2 --local-dir $DATA/models/VoxCPM2 \
    || die "VoxCPM2 权重下载失败"
fi
mkdir -p /root/VoxCPM/pretrained_models
ln -sfn $DATA/models/VoxCPM2 /root/VoxCPM/pretrained_models/VoxCPM2

if [ $TTS_ONLY -eq 1 ]; then
  step "TTS-only 模式，跳过 Ollama。完成！"
  exit 0
fi

step "[4] Ollama 二进制"
# 坑5: 官方 install.sh 下到的二进制在部分容器里段错误；且新版本发行物已改名
# ollama-linux-amd64.tar.zst（旧 .tgz 地址 404）。直接下载指定版本的 tar.zst，
# 国内直连失败自动走 gh-proxy 镜像。
OLLAMA_VER=v0.32.4
if ! ollama --version >/dev/null 2>&1; then
  rm -rf /usr/local/bin/ollama /usr/local/lib/ollama /root/ollama.tar.zst
  URL="https://github.com/ollama/ollama/releases/download/$OLLAMA_VER/ollama-linux-amd64.tar.zst"
  turbo_on;  curl -fL --retry 3 -C - -o /root/ollama.tar.zst "$URL" \
    || { turbo_off; curl -fL --retry 5 -C - -o /root/ollama.tar.zst "https://gh-proxy.com/$URL"; } \
    || die "ollama 下载失败"
  tar --zstd -xf /root/ollama.tar.zst -C /usr/local || die "ollama 解压失败"
  ollama --version >/dev/null 2>&1 || die "ollama 二进制不可用（段错误?）"
fi

step "[5] LLM 模型 (~13G, 存数据盘)"
# 坑6: ollama pull 必须直连（学术加速代理会毁掉 registry 连接）
turbo_off
export OLLAMA_MODELS=$DATA/ollama-models
mkdir -p $OLLAMA_MODELS
fuser -k 11434/tcp 2>/dev/null; sleep 1
(OLLAMA_MODELS=$OLLAMA_MODELS nohup ollama serve > /root/ollama.log 2>&1 &)
sleep 6
ollama list >/dev/null 2>&1 || die "ollama server 起不来，看 /root/ollama.log"

if ! ollama list | awk '{print $1}' | grep -qx "gpt-oss-agent:32k"; then
  # 坑7: 长时间下载速度会衰减到 KB/s 级；重启 pull 会从断点继续并重置限速。
  # 自动循环：每轮最多 10 分钟，没下完就重启，最多 30 轮。
  # 坑8: 异常中断(关机)会留下损坏的 partial 分片，报
  # "remove ...-partial-N: no such file or directory" 或 "Error: EOF"，
  # 此时唯一可靠的办法是清掉 partial 重来。
  for round in $(seq 1 30); do
    echo "--- pull round $round ---"
    timeout 600 ollama pull huihui_ai/gpt-oss-abliterated:latest && { PULLED=1; break; }
    rc=$?
    if [ $rc -ne 124 ]; then   # 非超时的真实报错 → 检查 partial 损坏
      if grep -qE 'partial-[0-9]+: no such file|Error: EOF' /root/ollama.log 2>/dev/null \
         || ollama pull huihui_ai/gpt-oss-abliterated:latest 2>&1 | grep -qE 'partial|EOF'; then
        echo "检测到损坏的 partial 分片，清理后重试..."
        rm -rf $OLLAMA_MODELS/blobs/*partial*
      fi
    fi
  done
  [ "${PULLED:-0}" = "1" ] || die "LLM 下载失败（30 轮超限）"
  ollama create gpt-oss-agent:32k -f /root/claude_code_src_Modelfile 2>/dev/null \
    || ollama create gpt-oss-agent:32k -f /root/Modelfile \
    || die "ollama create 失败（Modelfile 没上传?）"
fi

step "[6] 验证"
ollama list
$PY -c "import torch; print('CUDA:', torch.cuda.is_available(), torch.cuda.get_device_name(0))"
df -h $DATA
echo "=== 全部完成 ==="
echo "显存提示：gpt-oss 20B F16 需要 ~18G 显存才能全进 GPU；"
nvidia-smi --query-gpu=memory.total --format=csv,noheader
echo "低于 18G 时 LLM 会主要跑在 CPU 上（很慢），建议该机器只用 TTS，LLM 用别的后端。"
