#!/usr/bin/env bash
set -euo pipefail

# Start the Ollama server in the background. The model is already baked into
# /root/.ollama/models, so no download happens at runtime.
ollama serve >/tmp/ollama.log 2>&1 &
OLLAMA_PID=$!

# When the container stops, take Ollama down with us.
trap 'kill "$OLLAMA_PID" 2>/dev/null || true' EXIT INT TERM

# Wait for the Ollama HTTP API to accept connections before starting bubu.
echo "Waiting for Ollama to be ready..."
for i in $(seq 1 60); do
  if curl -fsS http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "Ollama is ready."
    break
  fi
  if ! kill -0 "$OLLAMA_PID" 2>/dev/null; then
    echo "Ollama server exited unexpectedly. Logs:" >&2
    cat /tmp/ollama.log >&2
    exit 1
  fi
  sleep 1
done

# Launch bubu with the Ollama settings baked in. Any extra args passed to
# `docker compose run` land here (e.g. a one-shot prompt).
exec node /opt/bubu/package/cli.js --settings /opt/bubu/settings-ollama.json "$@"
