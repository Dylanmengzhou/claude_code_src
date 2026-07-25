# bubu — 用 Docker 一键在本地跑（模型已内置）

这份指南教你把这个仓库 clone 下来后，用 **Docker** 启动 `bubu`（Claude Code 2.1.88）。

**模型（`gpt-oss-agent:32k`）和 Ollama 服务都已经打包进镜像里**，所以：

- ✅ 不需要在电脑上单独安装 Ollama
- ✅ 不需要联网下载模型
- ✅ 不需要改任何配置

只要装了 Docker，`build` + `run` 两条命令就能跑。全程不调用任何官方 API，不需要登录 Anthropic 账号。

适用系统：**Windows / Linux / macOS**。

---

## 目录

1. [它是什么 / 工作原理](#1-它是什么--工作原理)
2. [唯一的准备：安装 Docker](#2-唯一的准备安装-docker)
3. [下载并启动 bubu](#3-下载并启动-bubu)
4. [日常使用](#4-日常使用)
5. [常见问题排查](#5-常见问题排查)

---

## 1. 它是什么 / 工作原理

- `bubu` 是终端里的 AI 编程助手（Claude Code 2.1.88 的构建产物）。
- 它默认调用 Anthropic 的云端 API，但这里被配置成调用 **本地 Ollama** 跑的开源大模型。
- **关键区别**：Ollama 服务和模型权重都在同一个容器里，容器一启动就自动把 Ollama 拉起来，bubu 直连 `localhost:11434`。你什么都不用配。

数据流长这样（全部发生在同一个容器内）：

```
你在终端输入
      │
      ▼
┌───────────────────────────────────────────────┐
│  Docker 容器                                    │
│                                                 │
│  ┌──────────┐   HTTP :11434   ┌──────────────┐ │
│  │  bubu    │ ───────────────▶│  Ollama       │ │
│  │          │ ◀───────────────│  (内置模型)    │ │
│  └──────────┘                 └──────────────┘ │
└───────────────────────────────────────────────┘
```

---

## 2. 唯一的准备：安装 Docker

| 系统 | 怎么装 |
|------|--------|
| **Windows** | 下载并安装 [Docker Desktop](https://www.docker.com/products/docker-desktop/)。安装时按提示启用 WSL 2。装完打开 Docker Desktop，等状态变成绿色 “running”。|
| **macOS** | 下载 [Docker Desktop](https://www.docker.com/products/docker-desktop/) 安装并打开。|
| **Linux** | 安装 [Docker Engine](https://docs.docker.com/engine/install/) 和 [Docker Compose 插件](https://docs.docker.com/compose/install/linux/)。|

装好后，打开终端（Windows 用 **PowerShell**）验证：

```bash
docker --version
docker compose version
```

两条都能打印版本号就 OK。

> **磁盘要求**：镜像里包含约 13.8GB 的模型权重，构建后镜像约 **14~15GB**。请确保 Docker 有足够的磁盘空间。

---

## 3. 下载并启动 bubu

### 第一步：克隆仓库

```bash
git clone <这个仓库的地址>
cd <仓库目录名>
```

> ⚠️ 模型权重（`ollama-models/` 目录，约 13.8GB）需要随仓库一起获得。如果仓库通过
> Git LFS 或其他方式分发大文件，请确认该目录已完整下载后再构建。

### 第二步：构建镜像（只需第一次）

```bash
docker compose build
```

> 这一步会把 Ollama 和模型打进镜像，构建时间取决于机器，模型层较大请耐心等待。

### 第三步：启动 bubu

```bash
docker compose run --rm bubu
```

启动时会先看到 `Waiting for Ollama to be ready...`，等内置的 Ollama 服务就绪后，
就会进入 bubu 的终端界面。直接开聊 / 让它写代码即可。

> **它在哪操作文件？** 你在**哪个目录**执行 `docker compose run`，
> bubu 就把**那个目录**当作工作区（在容器里叫 `/workspace`）。
> 想让它改哪个项目，就先 `cd` 进那个项目目录，再从那里跑这条命令。
>
> Windows 用户请在 **PowerShell** 或 **WSL** 里运行，别用老式 CMD，否则目录挂载可能失败。

---

## 4. 日常使用

在你想让 bubu 帮忙的项目目录下运行：

```bash
docker compose run --rm bubu
```

- `--rm` 表示用完自动清理这个临时容器（你的配置和会话不会丢，见下）。
- 想直接给一个任务而不进交互界面，可以在后面加参数，例如：

  ```bash
  docker compose run --rm bubu -p "帮我把这个函数加上注释"
  ```

**你的登录状态 / 会话历史 / 设置**保存在一个叫 `bubu-config` 的 Docker 卷里，
容器删了也不会丢，下次启动自动带回来。

---

## 5. 常见问题排查

**Q：`docker compose build` 报 daemon 相关错误 / 连不上 Docker。**
Docker 没启动。Windows/Mac 打开 Docker Desktop 等它变绿；Linux 执行 `sudo systemctl start docker`。

**Q：构建失败，提示空间不足 / no space left on device。**
镜像约 14~15GB。在 Docker Desktop 设置里调大磁盘镜像上限，或清理无用镜像：`docker system prune -a`。

**Q：启动后一直卡在 `Waiting for Ollama to be ready...`。**
Ollama 在容器内启动失败。查看日志：
```bash
docker compose run --rm --entrypoint sh bubu -c "ollama serve"
```
观察报错信息。也可能是模型层没打全（见下一条）。

**Q：提示 model not found / 找不到 `gpt-oss-agent:32k`。**
说明 `ollama-models/` 目录在构建时不完整（大文件没下全）。确认该目录里
`blobs/` 下有一个约 13.8GB 的文件，重新完整获取后再 `docker compose build`。

**Q：模型回答很慢。**
容器内的 Ollama 默认用 **CPU** 推理（除非你为 Docker 配置了 GPU 直通）。这个 20B 模型在纯 CPU 上会比较慢，属正常现象，与 Docker 本身无关。

**Q：Windows 下工作目录挂载不进去 / bubu 看不到我的文件。**
请在 **PowerShell** 或 **WSL** 里运行命令（不要用 CMD）。确保你已经 `cd` 到目标项目目录。

**Q：我改了 `Dockerfile` 或 `settings-ollama.docker.json`，但没生效。**
改了这些需要重新 `docker compose build`。
