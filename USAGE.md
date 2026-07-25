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

**macOS / Linux：**
```bash
podman run --rm -it \
  -v "$PWD:/workspace" \
  -v bubu-config:/root/.bubu \
  -v ollama-data:/root/.ollama \
  bubu:2.1.88
```

**Windows（PowerShell）：**
```powershell
podman run --rm -it `
  -v "${PWD}:/workspace" `
  -v bubu-config:/root/.bubu `
  -v ollama-data:/root/.ollama `
  bubu:2.1.88
```

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

---

有问题先看上面的“常见问题”，绝大多数是磁盘空间或虚拟机没启动。
