# CUDA runtime base so Ollama can use an NVIDIA GPU when one is exposed to the
# container. Ollama auto-detects the GPU at runtime: with GPU access it uses
# CUDA, otherwise it transparently falls back to CPU. One image works for GPU
# and non-GPU hosts (incl. Mac = CPU).
#
# NOTE (China networks): the base image is pulled from Docker Hub. If you can't
# reach registry-1.docker.io, configure a mirror in
# ~/.config/containers/registries.conf (see USAGE.md) and restart the machine.
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

# ---------------------------------------------------------------------------
# Mirror switch. Default (CN=0) uses official upstream sources — correct for
# users OUTSIDE China. Users in China build with `--build-arg CN=1` to route
# apt + Node downloads through domestic mirrors (Aliyun / Tsinghua).
# ---------------------------------------------------------------------------
ARG CN=0

# Let the NVIDIA container runtime expose the GPU. Harmless when no GPU present.
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# apt: swap to the Aliyun mirror only when CN=1.
RUN if [ "$CN" = "1" ]; then \
        sed -i 's|http://archive.ubuntu.com|https://mirrors.aliyun.com|g; s|http://security.ubuntu.com|https://mirrors.aliyun.com|g' /etc/apt/sources.list ; \
    fi \
    && apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 prebuilt binary. Official nodejs.org by default; Tsinghua when CN=1.
ARG NODE_VERSION=v20.18.1
RUN if [ "$CN" = "1" ]; then \
        NODE_BASE="https://mirrors.tuna.tsinghua.edu.cn/nodejs-release" ; \
    else \
        NODE_BASE="https://nodejs.org/dist" ; \
    fi \
    && curl -fsSL "${NODE_BASE}/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz" -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && node --version

# Ollama — pinned release tarball from GitHub (works from both China and
# abroad; more reliable than the install.sh script or the "latest" URL).
ARG OLLAMA_VERSION=v0.11.4
RUN curl -fsSL "https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}/ollama-linux-amd64.tgz" -o /tmp/ollama.tgz \
    && tar -xzf /tmp/ollama.tgz -C /usr \
    && rm /tmp/ollama.tgz \
    && ollama --version || true

# The bubu-code package (Claude Code 2.1.88), driven by the bundled Ollama backend
COPY bubu-package /opt/bubu/package

# Container settings: Ollama runs inside this container, so the base URL points
# at localhost. Runtime env vars from compose still override these values.
COPY settings-ollama.docker.json /opt/bubu/settings-ollama.json

# Modelfile used to build gpt-oss-agent:32k from the public base model on first run.
COPY Modelfile /opt/bubu/Modelfile

# Entrypoint: starts ollama serve, builds the model on first run, then bubu.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Isolated config dir (login/session state) — mounted as a volume to persist
ENV CLAUDE_CONFIG_DIR=/root/.bubu

# Persist bubu config AND downloaded Ollama models across runs, so the ~13GB
# model download only happens once.
VOLUME ["/root/.bubu", "/root/.ollama"]

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
