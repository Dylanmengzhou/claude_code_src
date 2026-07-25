FROM node:20-slim

# git for repo operations; ripgrep/audio binaries ship inside vendor/.
# curl is needed to install Ollama and health-check it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Install the Ollama server into the image so the container is fully
# self-contained — no host-side Ollama required.
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
