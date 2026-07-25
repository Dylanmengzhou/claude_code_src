# CUDA runtime base so Ollama can use an NVIDIA GPU when one is exposed to the
# container. Ollama auto-detects the GPU at runtime: if the container was
# started WITH GPU access it uses CUDA, otherwise it transparently falls back
# to CPU. So this single image works everywhere (GPU or not, incl. Mac = CPU).
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

# Let the NVIDIA container runtime expose the GPU + compute/utility caps.
# Harmless when no GPU is present.
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# System deps: git for repo ops, curl/ca-certificates for installers.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl gnupg \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 (NodeSource) — bubu runs on Node.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Ollama server (its installer bundles the CUDA-capable runtime libs).
RUN curl -fsSL https://ollama.com/install.sh | sh

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
