# bubu 使用手册（用 Podman 一键跑本地 AI 编程助手）

这是一份**从零开始、照着做就能跑起来**的手册。跟着一步步来即可，不需要懂 Docker/AI 原理。

`bubu` 是一个跑在终端里的 AI 编程助手（Claude Code 2.1.88），它使用一个**本地大模型**（不联网调用任何付费 API，不用登录任何账号）。模型会在**第一次运行时自动下载**，你什么都不用手动配。

适用系统：**macOS / Linux / Windows**。

---

## 你需要准备什么

- 一台能装 **Podman** 的电脑（Docker 也行，命令把 `podman` 换成 `docker` 即可）。
- **硬盘至少留 40GB 空闲**（模型约 13GB，加上镜像和运行空间）。
- **能联网**（仅第一次下载模型时需要，之后可离线用）。

---

## 第一步：安装 Podman

| 系统 | 怎么装 |
|------|--------|
| **macOS** | 装 [Podman Desktop](https://podman-desktop.io/)，或用 Homebrew：`brew install podman` |
| **Windows** | 装 [Podman Desktop](https://podman-desktop.io/)，按提示启用 WSL2 |
| **Linux** | 用系统包管理器，如 Ubuntu：`sudo apt install podman` |

装好后，打开终端（Windows 用 **PowerShell**）验证能用：

```bash
podman --version
```

能打印版本号就 OK。

### macOS / Windows 额外一步：创建并启动虚拟机

macOS 和 Windows 上，Podman 需要一个 Linux 虚拟机来跑容器。**磁盘一定要给足**（放得下 13GB 模型）：

```bash
podman machine init --disk-size 60 --cpus 4 --memory 8192
podman machine start
```

> `--disk-size 60` 是 60GB，务必给够。第一次会下载一个基础系统镜像，等几分钟。
> Linux 用户跳过这一步。

验证虚拟机在运行：

```bash
podman machine list
```

看到状态是 “Currently running” 就 OK。

---

## 第二步：拿到项目代码

```bash
git clone https://github.com/Dylanmengzhou/claude_code_src.git
cd claude_code_src
```

> 如果对方直接把文件夹发给你（压缩包），解压后 `cd` 进那个目录即可，跳过 `git clone`。

---

## 第三步：构建镜像（只需第一次）

```bash
podman build -t bubu:2.1.88 .
```

> 这一步安装 bubu 和 Ollama，需要几分钟。**注意：这一步还不会下载 13GB 的模型**，模型是在你第一次“运行”时才下载的。

---

## 第四步：运行 bubu

**在你想让 bubu 帮忙的项目目录里**运行下面的命令。它会把当前目录作为工作区。

> 🚀 **有 NVIDIA 显卡想用 CUDA 加速？** 先看下面的[「开启 GPU 加速」](#开启-gpu-加速nvidia-显卡)一节，
> 配好之后在命令里**加一行** `--device nvidia.com/gpu=all` 即可（见下方带 GPU 的示例）。
> 没有 N 卡就用不带那一行的版本，会自动用 CPU。

**macOS / Linux（CPU）：**
```bash
podman run --rm -it \
  -v "$PWD:/workspace" \
  -v bubu-config:/root/.bubu \
  -v ollama-data:/root/.ollama \
  bubu:2.1.88
```

**Linux / Windows-WSL（带 NVIDIA GPU 加速）：**
```bash
podman run --rm -it \
  --device nvidia.com/gpu=all \
  -v "$PWD:/workspace" \
  -v bubu-config:/root/.bubu \
  -v ollama-data:/root/.ollama \
  bubu:2.1.88
```

**Windows（PowerShell，CPU）：**
```powershell
podman run --rm -it `
  -v "${PWD}:/workspace" `
  -v bubu-config:/root/.bubu `
  -v ollama-data:/root/.ollama `
  bubu:2.1.88
```

> 启动后会打印一行提示：看到 `GPU detected — Ollama will use CUDA acceleration.`
> 说明 GPU 生效了；看到 `running on CPU` 则是在用 CPU。

### 第一次运行会发生什么？

1. 屏幕显示 `Waiting for Ollama to start...`
2. 然后显示 `First run: downloading base model ...（~13GB，会比较久）`
   —— **这一步在下载模型，取决于网速可能要几十分钟，耐心等，只需一次。**
3. 下载完自动构建 32k 版本，然后进入 bubu 的界面。

**之后再运行，模型已经存下来了，会直接秒进界面。**

---

## 日常怎么用

- 想让 bubu 帮某个项目干活，就先 `cd` 进那个项目目录，再执行第四步的 `podman run ...` 命令。
- 进入界面后，直接用中文/英文描述你的需求即可，比如“帮我给这个函数加注释”“找出这段代码的 bug”。
- 想一句话直接下任务、不进交互界面，在命令末尾加 `-p`：
  ```bash
  podman run --rm -it -v "$PWD:/workspace" -v bubu-config:/root/.bubu -v ollama-data:/root/.ollama \
    bubu:2.1.88 -p "帮我把这个函数加上注释"
  ```

> 你的会话历史、设置会保存在 `bubu-config` 和 `ollama-data` 这两个存储里，容器删了也不丢，下次自动带回来。

---

## 用 compose 更省事（可选）

项目里带了 `compose.yaml`，如果你的 Podman 支持 compose，可以用更短的命令：

```bash
podman compose build          # 相当于第三步
podman compose run --rm bubu  # 相当于第四步，卷都自动挂好
```

> 如果 `podman compose` 报“找不到 compose provider”，说明你的环境没装 compose 插件，直接用上面第三、四步的原生命令即可，效果一样。

---

## 开启 GPU 加速（NVIDIA 显卡）

镜像**自动兼容**：暴露了 GPU 就用 CUDA 加速，没有就用 CPU，**同一个镜像不用改**。
要用上显卡，需要一次性配置好宿主机，让容器能“看到”显卡。

> ⚠️ 仅 **NVIDIA 显卡**支持。AMD 显卡和 **Mac** 用不了 CUDA（Mac 只能 CPU）。

### Windows（你多半是这种）

1. **装最新 NVIDIA 显卡驱动**（[官网下载](https://www.nvidia.com/Download/index.aspx)），Windows 版驱动已自带 WSL 的 GPU 支持。
2. 确保 Podman 用的是 **WSL2** 后端（`podman machine` 在 Windows 上跑在 WSL2 里）。
3. 在 **WSL2 里**安装 NVIDIA Container Toolkit（让容器能透传 GPU）：
   ```bash
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
   curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
     sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
     sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
   ```
4. 生成 Podman 能识别的 GPU 配置（CDI）：
   ```bash
   sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
   ```
5. 验证能列出显卡：
   ```bash
   nvidia-ctk cdi list
   ```
   能看到 `nvidia.com/gpu=all` 就 OK。

配好后，运行 bubu 时用**带 `--device nvidia.com/gpu=all` 的那条命令**（见第四步）。

### Linux

步骤和上面第 3~5 步一样（直接在系统里执行，不用进 WSL）：装最新 NVIDIA 驱动 → 装
NVIDIA Container Toolkit → `nvidia-ctk cdi generate` → 运行时加 `--device nvidia.com/gpu=all`。

### 怎么确认真的用上了 GPU

启动 bubu 时留意开头那行日志：
- `GPU detected — Ollama will use CUDA acceleration.` → 显卡生效 ✅
- `No GPU exposed to the container — running on CPU.` → 还在用 CPU，回到上面检查配置。

---

## 常见问题

**Q：一直卡在 “downloading base model”。**
在下 13GB 模型，正常。慢是网速问题。中断了重跑会**断点续传**，已下的不会白下。

**Q：`podman build` 报 “no space left on device” / 空间不足。**
虚拟机磁盘不够。删掉重建并给更大磁盘：
```bash
podman machine stop
podman machine rm
podman machine init --disk-size 80 --cpus 4 --memory 8192
podman machine start
```

**Q：连不上 Podman / 提示 socket 错误。**
虚拟机没启动。跑 `podman machine start`（macOS/Windows）。

**Q：模型回答很慢。**
本地模型靠 CPU 跑（除非配了 GPU），这个模型较大，慢是正常的，跟你的电脑性能有关，不是 bug。

**Q：bubu 看不到我的文件。**
确认你是在**目标项目目录里**运行的命令，并且命令里带了 `-v "$PWD:/workspace"`。Windows 请用 PowerShell，别用 CMD。

**Q：想重新下载 / 换模型。**
删掉模型存储卷即可重来：`podman volume rm ollama-data`（会导致下次运行重新下载 13GB）。

**Q：我有 N 卡，但启动显示 “running on CPU”。**
GPU 没透传进容器。检查：① 运行命令是否带了 `--device nvidia.com/gpu=all`；② 是否装了
NVIDIA Container Toolkit 并执行了 `nvidia-ctk cdi generate`（见「开启 GPU 加速」）；
③ Windows 用户确认在 WSL2 里配的、驱动是最新版。

**Q：`--device nvidia.com/gpu=all` 报错找不到设备。**
说明 CDI 配置没生成。重跑 `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`，
再用 `nvidia-ctk cdi list` 确认列出了 `nvidia.com/gpu=all`。

---

有问题先看上面的“常见问题”，绝大多数是磁盘空间或虚拟机没启动。
