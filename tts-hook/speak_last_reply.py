#!/usr/bin/env python3
"""Claude Code Stop hook: speak the last assistant reply via VoxCPM.

Reads the Stop-hook JSON from stdin ({"transcript_path": ...}), extracts the
last assistant text message from the transcript JSONL, cleans it up for
speech, sends it to the resident VoxCPM infer_server (infer_server.py) over
its line-delimited JSON TCP protocol, and plays the resulting wav with afplay.

Env overrides:
  VOX_HOST       infer server host   (default 127.0.0.1)
  VOX_PORT       infer server port   (default 8850)
  VOX_BASE_DIR   VoxCPM repo dir, wav paths are relative to it
                 (default /Users/dylanmengzhou/Developer/VoxCPM)
  VOX_REMOTE     "user@host:port" of the server running infer_server.
                 When set, the wav is fetched back via scp before playing
                 and VOX_BASE_DIR is interpreted as the REMOTE repo dir.
  VOX_REF        reference wav for voice cloning (default jarvis_ref.wav in
                 VOX_BASE_DIR; set to empty string to disable)
  VOX_LORA       LoRA dir passed to the server (default none; ignored when
                 VOX_REF is set — reference cloning wins)
  VOX_TIMESTEPS  diffusion steps (default 5)
  VOX_MAX_CHARS  truncate spoken text (default 400)
  VOX_FG         set to 1 to run in foreground (debugging)

The hook must never block or fail the agent: by default it re-launches itself
detached and exits 0 immediately; all errors are swallowed (logged to
/tmp/speak_hook.log).
"""

import json
import os
import re
import socket
import subprocess
import sys
import tempfile

LOG = "/tmp/speak_hook.log"


def log(msg):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(msg.rstrip() + "\n")
    except OSError:
        pass


def last_assistant_text(transcript_path):
    """Return the text of the last assistant message in the JSONL transcript."""
    text = None
    try:
        with open(transcript_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if entry.get("type") != "assistant":
                    continue
                content = (entry.get("message") or {}).get("content")
                if isinstance(content, str):
                    if content.strip():
                        text = content
                    continue
                if not isinstance(content, list):
                    continue
                parts = [
                    b.get("text", "")
                    for b in content
                    if isinstance(b, dict) and b.get("type") == "text"
                ]
                joined = "\n".join(p for p in parts if p.strip())
                if joined.strip():
                    text = joined
    except OSError as e:
        log(f"read transcript failed: {e}")
    return text


def clean_for_speech(text, max_chars):
    # Fenced code blocks are unreadable aloud
    text = re.sub(r"```.*?```", "（代码略）", text, flags=re.S)
    # Markdown tables
    text = re.sub(r"^\|.*\|$", "", text, flags=re.M)
    # Links: keep the label
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    # Inline code: keep content
    text = re.sub(r"`([^`]*)`", r"\1", text)
    # Headings / emphasis / list markers
    text = re.sub(r"^#{1,6}\s*", "", text, flags=re.M)
    text = re.sub(r"[*_>#]", "", text)
    text = re.sub(r"^\s*[-•]\s*", "", text, flags=re.M)
    # File paths read terribly; shorten to basename
    text = re.sub(r"(/[\w.\-]+){3,}", lambda m: m.group(0).rsplit("/", 1)[-1], text)
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > max_chars:
        cut = text[:max_chars]
        # try to end on a sentence boundary
        m = re.search(r"[。！？.!?][^。！？.!?]*$", cut)
        if m:
            cut = cut[: m.start() + 1]
        text = cut
    return text


def synthesize(text):
    host = os.environ.get("VOX_HOST", "127.0.0.1")
    port = int(os.environ.get("VOX_PORT", "8850"))
    remote = os.environ.get("VOX_REMOTE", "")
    # Paths in the request/response are on whatever machine runs infer_server:
    # remote mode → server-side paths; local mode → this machine's paths.
    base = os.environ.get(
        "VOX_BASE_DIR",
        "/root/VoxCPM" if remote else os.path.expanduser("~/Developer/VoxCPM"),
    )
    default_ref = os.path.join(base, "jarvis_ref.wav")
    if remote:
        # Can't stat remote files cheaply; assume the default ref exists
        # (server_setup uploads it). Override with VOX_REF="" to disable.
        ref = os.environ.get("VOX_REF", default_ref)
    else:
        ref = os.environ.get(
            "VOX_REF", default_ref if os.path.exists(default_ref) else ""
        )
    req = {
        "text": text,
        "lora": "" if ref else os.environ.get("VOX_LORA", ""),
        "cfg": 2.0,
        "timesteps": int(os.environ.get("VOX_TIMESTEPS", "5")),
        "seed": None,
    }
    if ref:
        req["reference_wav_path"] = ref
    with socket.create_connection((host, port), timeout=10) as s:
        s.settimeout(600)  # generation itself can be slow on MPS
        f = s.makefile("rwb")
        f.write((json.dumps(req, ensure_ascii=False) + "\n").encode("utf-8"))
        f.flush()
        resp = json.loads(f.readline().decode("utf-8"))
    if not resp.get("ok"):
        raise RuntimeError(resp.get("error", "unknown server error"))
    wav = resp["wav"]
    if not os.path.isabs(wav):
        wav = os.path.join(base, wav)

    if remote:
        # wav lives on the server; scp it back to a local temp file
        m = re.match(r"^(.*?)(?::(\d+))?$", remote)
        target, port = m.group(1), m.group(2)
        local = os.path.join(
            tempfile.gettempdir(), "vox_" + os.path.basename(wav)
        )
        # Only pass -P when a port was given explicitly; otherwise let
        # ~/.ssh/config decide (VOX_REMOTE may be a config alias).
        cmd = ["scp", "-o", "BatchMode=yes"]
        if port:
            cmd += ["-P", port]
        cmd += [f"{target}:{wav}", local]
        subprocess.run(cmd, check=True, capture_output=True, timeout=120)
        return local
    return wav


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        payload = {}
    transcript = payload.get("transcript_path") or (
        sys.argv[1] if len(sys.argv) > 1 else None
    )
    if not transcript:
        log("no transcript_path in hook payload")
        return

    # Detach so the Stop hook returns instantly; the child does the slow work.
    if os.environ.get("VOX_FG") != "1" and "--child" not in sys.argv:
        subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), transcript, "--child"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return

    text = last_assistant_text(transcript)
    if not text:
        log("no assistant text found")
        return
    text = clean_for_speech(text, int(os.environ.get("VOX_MAX_CHARS", "400")))
    if not text:
        return
    log(f"speaking: {text[:80]}...")
    try:
        wav = synthesize(text)
    except Exception as e:
        log(f"synthesize failed: {e}")
        return
    play(wav)


def play(wav):
    """Play a wav with the first available player (macOS/Linux/Windows)."""
    import shutil

    for player in (
        ["afplay", wav],                       # macOS
        ["paplay", wav],                       # Linux PulseAudio
        ["aplay", "-q", wav],                  # Linux ALSA
        ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", wav],
        ["powershell", "-c",
         f"(New-Object Media.SoundPlayer '{wav}').PlaySync()"],  # Windows
    ):
        if shutil.which(player[0]):
            try:
                subprocess.run(player, check=False)
                return
            except OSError as e:
                log(f"{player[0]} failed: {e}")
    log("no audio player found (tried afplay/paplay/aplay/ffplay/powershell)")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # never break the agent
        log(f"unexpected: {e}")
    sys.exit(0)
