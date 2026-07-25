FROM node:20-slim

# git for repo operations; ripgrep/audio binaries ship inside vendor/.
# curl is needed to install Ollama.
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

# Bake the gpt-oss-agent:32k model (blobs + manifest) into Ollama's default
# store. This is the ~13.8GB model layer plus its license/template/params.
COPY ollama-models /root/.ollama/models

# Entrypoint script: starts `ollama serve` in the background, waits for it to be
# ready, then launches bubu against it.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Isolated config dir (login/session state) — mounted as a volume to persist
ENV CLAUDE_CONFIG_DIR=/root/.bubu
VOLUME ["/root/.bubu"]

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
