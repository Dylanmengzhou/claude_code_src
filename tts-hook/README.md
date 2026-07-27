# tts-hook — 让 bubu 用克隆声音说话（贾维斯模式）

bubu 每次回复结束后，自动把回复文本用 [VoxCPM2](https://github.com/OpenBMB/VoxCPM) 语音克隆合成并播放。
语音合成跑在一台 GPU 服务器上（以 AutoDL 为例），你的电脑只负责播放。

```
你的电脑                                GPU 服务器 (AutoDL)
┌──────────────────────┐               ┌──────────────────────────┐
│ bubu (cli.js)        │               │ infer_server.py :8850    │
│  └─ Stop hook        │── SSH 隧道 ──▶│   VoxCPM2 + 参考音频      │
│      speak_last_reply│◀── scp wav ───│                          │
│  └─ 播放器 (afplay…) │               │ ollama :11434 (可选)     │
└──────────────────────┘               └──────────────────────────┘
```

## 一、服务器端（只需一次）

1. 租一台 GPU 主机（AutoDL 亲测可用；显存 ≥8G 即可跑 TTS）。
2. 上传本目录的三个文件到服务器：

   ```bash
   scp -P <端口> tts-hook/server_setup.sh tts-hook/server_start.sh root@<服务器>:/root/
   # 你的声音参考音频（16kHz 单声道 wav，3-10 秒即可）：
   scp -P <端口> jarvis_ref.wav root@<服务器>:/root/   # 装完后 mv 到 /root/VoxCPM/
   # 如果要跑 LLM，还需上传仓库根目录的 Modelfile 到 /root/Modelfile
   ```

   > `infer_server.py` 已包含在 VoxCPM 仓库里，clone 时自带，无需单独上传
   > （本目录里的副本仅作备份）。

3. 在服务器上执行（建议放 tmux，全程无人值守，可反复重跑）：

   ```bash
   tmux new -s setup 'bash /root/server_setup.sh --tts-only'   # 只装语音（推荐）
   # 或完整安装（TTS + 13G 的 LLM）：tmux new -s setup 'bash /root/server_setup.sh'
   ```

   装完把参考音频放进仓库：`mv /root/jarvis_ref.wav /root/VoxCPM/`

4. **以后每次开机**只需：`bash /root/server_start.sh --tts-only`

> 模型权重都放在 `/root/autodl-tmp`（AutoDL 数据盘），关机不丢，
> 重开机不用重新下载。

## 二、你的电脑端（只需一次）

1. 配置免密 SSH。在 `~/.ssh/config` 里加（端口/地址按你的实例改，
   AutoDL 每次重开机端口可能变，来这里同步改）：

   ```
   Host autodl-vox
     HostName region-xx.seetacloud.com
     Port 12345
     User root
     IdentityFile ~/.ssh/autodl_vox
     IdentitiesOnly yes
   ```

   生成并安装密钥：

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/autodl_vox -N ""
   ssh-copy-id -i ~/.ssh/autodl_vox.pub -p <端口> root@<服务器>
   ssh autodl-vox echo ok    # 能免密打印 ok 即成功
   ```

2. 需要 Python 3（macOS 自带）。播放器按平台自动选择：
   macOS 用 afplay（自带）；Linux 需要 paplay/aplay/ffplay 之一；
   Windows 用 PowerShell（自带）。

3. 安装 hook 脚本到固定位置（settings 里的 hook 指向这里，
   这样在任何目录启动 bubu 都能找到）：

   ```bash
   mkdir -p ~/.claude/tts-hook
   cp tts-hook/speak_last_reply.py ~/.claude/tts-hook/
   ```

## 三、日常使用

```bash
bash tts-hook/connect.sh              # 1. 挂隧道（开机一次即可）
node bubu-package/cli.js --settings settings-ollama-tts.json   # 2. 启动 bubu
```

之后每次 bubu 回复完，就会用克隆的声音念出来。

### settings 选哪个？

| 配置 | LLM 从哪来 | 说明 |
|---|---|---|
| `settings-ollama-tts.json` | 你电脑本地的 Ollama (11434) | 默认。想改用服务器上的 Ollama，把 `ANTHROPIC_BASE_URL` 改成 `http://localhost:11435`（隧道已映射） |
| `settings-modal-tts.json` | Modal 云端 | |
| `settings-hf-tts.json` | HuggingFace 路由 | |

三者的语音部分完全相同，都由 `VOX_REMOTE` 指向 SSH 别名。

### 密钥占位符（modal / hf 配置需要先填）

`settings-modal-tts.json` 和 `settings-hf-tts.json` 里的密钥字段是
`<尖括号占位符>`，**不填、原样运行会得到 401 认证错误**。用你自己的
账号信息替换掉整个尖括号（包括 `<` 和 `>`）：

| 文件 | 字段 | 去哪里拿 |
|---|---|---|
| `settings-modal-tts.json` | `ANTHROPIC_BASE_URL` | 你自己用 `modal-deploy/` 部署后，Modal 给出的 URL（含你的 Modal 用户名） |
| `settings-modal-tts.json` | `ANTHROPIC_AUTH_TOKEN` | 部署 modal-deploy 时你自己设定的 API 密钥（`sk-bubu-` 开头） |
| `settings-hf-tts.json` | `ANTHROPIC_AUTH_TOKEN` | [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) 创建一个 Read 权限的令牌（`hf_` 开头，免费） |

`settings-ollama-tts.json` 不需要任何密钥，开箱即用。

> 为什么不直接写真实密钥：这些密钥和你的账号/账单绑定，写进会被
> 分享的仓库等于把账号送人——HF 令牌能以你的身份调 API，Modal 密钥
> 会让别人用你的钱跑 GPU。**你自己填好密钥的版本不要提交/分享。**

> **显存提醒**：gpt-oss 20B 是 F16 精度、完整 18G，服务器显存低于
> 18G 时 Ollama 会把大部分层放到 CPU，速度会掉到几 token/s，没法用。
> 11G 显存的卡（2080 Ti 等）建议只跑 TTS，LLM 用本地/Modal/HF。

## 环境变量（都有合理默认值，一般不用动）

在 settings JSON 的 `env` 里设置：

| 变量 | 默认 | 说明 |
|---|---|---|
| `VOX_REMOTE` | 空 = 本机模式 | infer_server 所在的 SSH 别名（如 `autodl-vox`），设了就自动 scp 取回音频 |
| `VOX_HOST` / `VOX_PORT` | 127.0.0.1 / 8850 | infer_server 地址（走隧道时保持默认） |
| `VOX_BASE_DIR` | 远程 `/root/VoxCPM`，本机 `~/Developer/VoxCPM` | VoxCPM 仓库路径（在跑 infer_server 的那台机器上） |
| `VOX_REF` | `<BASE_DIR>/jarvis_ref.wav` | 参考音频。换声音就换这个文件；设为空串则改用 `VOX_LORA` |
| `VOX_LORA` | 空 | 微调 LoRA 目录（仅在 VOX_REF 为空时生效） |
| `VOX_TIMESTEPS` | 5 | 扩散步数，越大越慢越好听 |
| `VOX_MAX_CHARS` | 400 | 超长回复截断（按句子边界） |
| `VOX_FG` | 0 | 设 1 让 hook 前台阻塞运行（调试用），错误看 `/tmp/speak_hook.log` |

## 换成你自己的声音

录 3-10 秒清晰人声，转成 16kHz 单声道 wav 传上服务器即可：

```bash
afconvert -f WAVE -d LEI16@16000 -c 1 我的录音.mp3 my_ref.wav   # macOS
scp my_ref.wav autodl-vox:/root/VoxCPM/
# settings 的 env 里加: "VOX_REF": "/root/VoxCPM/my_ref.wav"
```

## 已踩过的坑（脚本都已自动处理，此处仅备查）

- AutoDL 学术加速（`/etc/network_turbo`）只能用于 GitHub/HF；
  **开着它跑 `ollama pull` 会失败**，脚本已按阶段开关。
- Ollama 官方 install.sh 在部分容器里装出来的二进制会段错误；
  新版发行物已改名 `.tar.zst`（旧 `.tgz` 地址 404）。脚本直接下
  固定版本 tar.zst，失败自动走 gh-proxy 镜像。
- 13G 模型长时间下载会被限速衰减到 KB/s，**重启 pull 即恢复且断点续传**，
  脚本已自动每 10 分钟循环重启。
- 下载中途关机会留下损坏的 partial 分片（报 `partial-N: no such file`
  或 `Error: EOF`），只能清掉 `blobs/*partial*` 重来，脚本已自动检测。
- 新 torch + 旧 einops 触发 dynamo 编译崩溃：启动加 `TORCHDYNAMO_DISABLE=1`。
- torchaudio 必须和 torch 主版本 + CUDA 后缀完全对齐，否则 `libcudart` 报错。
- 本机若装了 Ollama 会占 11434，隧道把远端映射到 **11435** 避开。
- Mac 的 scp 走 `~/.ssh/config` 别名时不要传 `-P`，否则覆盖配置端口。
