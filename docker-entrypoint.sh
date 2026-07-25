#!/usr/bin/env bash
set -euo pipefail

BASE_MODEL="huihui_ai/gpt-oss-abliterated:latest"
AGENT_MODEL="gpt-oss-agent:32k"

# Start the Ollama server in the background.
ollama serve >/tmp/ollama.log 2>&1 &
OLLAMA_PID=$!

# When the container stops, take Ollama down with us.
trap 'kill "$OLLAMA_PID" 2>/dev/null || true' EXIT INT TERM

# Wait for the Ollama HTTP API to accept connections.
echo "Waiting for Ollama to start..."
for i in $(seq 1 60); do
  if curl -fsS http://localhost:11434/api/tags >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$OLLAMA_PID" 2>/dev/null; then
    echo "Ollama server exited unexpectedly. Logs:" >&2
    cat /tmp/ollama.log >&2
    exit 1
  fi
  sleep 1
done

# Report whether Ollama found a GPU, so users can confirm CUDA acceleration.
if nvidia-smi >/dev/null 2>&1; then
  echo "GPU detected — Ollama will use CUDA acceleration."
else
  echo "No GPU exposed to the container — running on CPU."
  echo "(If you have an NVIDIA GPU, re-run with '--device nvidia.com/gpu=all'.)"
fi

# Build the agent model on first run. If it already exists (persisted via the
# ollama-data volume), this is skipped so startup is instant on later runs.
if ollama list | awk '{print $1}' | grep -qx "$AGENT_MODEL"; then
  echo "Model $AGENT_MODEL already present — skipping download."
else
  echo "First run: downloading base model $BASE_MODEL (~13GB, this can take a while)..."
  ollama pull "$BASE_MODEL"
  echo "Building $AGENT_MODEL (32k context)..."
  ollama create "$AGENT_MODEL" -f /opt/bubu/Modelfile
  echo "Model ready."
fi

# Launch bubu. Any extra args passed to `podman run` land here.
exec node /opt/bubu/package/cli.js --settings /opt/bubu/settings-ollama.json "$@"
