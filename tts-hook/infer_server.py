"""Resident VoxCPM inference process for the recorder app.

Loads the model ONCE and keeps it in memory, so repeated auditions only pay the
generation cost, not the ~13s model-load cost. Speaks a line-delimited JSON
protocol over a local TCP socket:

  request:  {"text": "...", "lora": "<dir or ''>", "cfg": 2.0, "timesteps": 10, "seed": null}
  response: {"ok": true, "wav": "data/me/_audition/xxx.wav", "dur": 4.1}
            {"ok": false, "error": "..."}

The model is (re)loaded lazily on the first request and whenever the requested
LoRA path changes. Run standalone for testing:

    python infer_server.py --port 8850 --model-path ./pretrained_models/VoxCPM2
"""

import argparse
import json
import os
import socket
import sys
import time
from pathlib import Path

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

import soundfile as sf


class ResidentModel:
    def __init__(self, model_path: str, device: str, base_dir: Path):
        self.model_path = model_path
        self.device = device
        self.base_dir = base_dir
        self.model = None
        self.loaded_lora = "\0"  # sentinel: nothing loaded yet
        self.out_dir = base_dir / "data" / "me" / "_audition"
        self.out_dir.mkdir(parents=True, exist_ok=True)
        self.progress_path = base_dir / "data" / "me" / "_tts_progress.json"

    def _set_progress(self, phase, done=0, total=0, note=""):
        try:
            self.progress_path.write_text(json.dumps(
                {"phase": phase, "done": done, "total": total, "note": note},
                ensure_ascii=False))
        except Exception:
            pass

    def _lora_paths(self, lora_dir: str):
        """Return (lora_config_path, lora_weights_path) or (None, None)."""
        if not lora_dir:
            return None, None
        d = Path(lora_dir)
        if not d.is_absolute():
            d = self.base_dir / d
        cfg = d / "lora_config.json"
        wts = d / "lora_weights.safetensors"
        if cfg.exists() and wts.exists():
            return str(cfg), str(wts)
        raise FileNotFoundError(f"LoRA not found under {d}")

    def ensure_loaded(self, lora_dir: str):
        if self.model is not None and self.loaded_lora == lora_dir:
            return
        self._set_progress("loading", note="正在加载模型…")
        from voxcpm import VoxCPM

        kwargs = dict(
            hf_model_id=self.model_path,
            load_denoiser=False,
            local_files_only=True,
            device=self.device,
        )
        if lora_dir:
            from voxcpm.model.voxcpm import LoRAConfig

            cfg_path, wts_path = self._lora_paths(lora_dir)
            with open(cfg_path, "r", encoding="utf-8") as f:
                info = json.load(f)
            cfg_dict = info.get("lora_config", info)
            kwargs["lora_config"] = LoRAConfig(**cfg_dict)
            kwargs["lora_weights_path"] = wts_path
        t0 = time.time()
        # Drop any previous model before loading a new one.
        self.model = None
        self.model = VoxCPM.from_pretrained(**kwargs)
        self.loaded_lora = lora_dir
        print(f"[infer] loaded model (lora={lora_dir or 'none'}) in {time.time()-t0:.1f}s",
              flush=True)

    def generate(self, req: dict) -> dict:
        text = (req.get("text") or "").strip()
        if not text:
            return {"ok": False, "error": "empty text"}
        lora = req.get("lora") or ""
        try:
            self.ensure_loaded(lora)
        except Exception as e:
            return {"ok": False, "error": f"load failed: {e}"}

        gen_kwargs = dict(
            text=text,
            cfg_value=float(req.get("cfg", 2.0)),
            inference_timesteps=int(req.get("timesteps", 10)),
        )
        ref = req.get("reference_wav_path")
        if ref:
            gen_kwargs["reference_wav_path"] = ref
        pt = req.get("prompt_text")
        pw = req.get("prompt_wav_path")
        if pt and pw:
            gen_kwargs["prompt_text"] = pt
            gen_kwargs["prompt_wav_path"] = pw
        seed = req.get("seed")
        if seed not in (None, "", "null"):
            gen_kwargs["seed"] = int(seed)

        try:
            import numpy as np
            t0 = time.time()
            sr = self.model.tts_model.sample_rate
            # Rough total-chunk estimate from text length, so the bar can move.
            # ~6 Chinese chars per audio chunk is a coarse heuristic; the real
            # count is unknown until generation ends, so we cap the displayed
            # fraction at 99% until done.
            est_total = max(4, len(text) // 4)
            chunks = []
            for i, chunk in enumerate(self.model.generate_streaming(**gen_kwargs)):
                chunks.append(chunk)
                self._set_progress("generating", done=i + 1, total=est_total,
                                   note="正在生成语音…")
            wav = np.concatenate(chunks) if chunks else np.zeros(1, dtype="float32")
            fname = f"audition_{int(t0)}.wav"
            out_path = self.out_dir / fname
            sf.write(str(out_path), wav, sr)
            dur = round(len(wav) / sr, 2)
            rel = str(out_path.relative_to(self.base_dir))
            self._set_progress("done", done=len(chunks), total=len(chunks),
                               note="完成")
            print(f"[infer] gen '{text[:20]}...' dur={dur}s in {time.time()-t0:.1f}s "
                  f"({len(chunks)} chunks)", flush=True)
            return {"ok": True, "wav": rel, "dur": dur}
        except Exception as e:
            self._set_progress("error", note=str(e))
            return {"ok": False, "error": f"generate failed: {e}"}


def serve(port: int, model_path: str, device: str, base_dir: Path):
    engine = ResidentModel(model_path, device, base_dir)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(4)
    print(f"[infer] resident inference server on 127.0.0.1:{port} "
          f"(base={base_dir}, device={device})", flush=True)

    while True:
        conn, _ = srv.accept()
        try:
            f = conn.makefile("rwb")
            line = f.readline()
            if not line:
                conn.close()
                continue
            try:
                req = json.loads(line.decode("utf-8"))
            except Exception as e:
                resp = {"ok": False, "error": f"bad request: {e}"}
            else:
                if req.get("cmd") == "ping":
                    resp = {"ok": True, "pong": True}
                else:
                    resp = engine.generate(req)
            f.write((json.dumps(resp, ensure_ascii=False) + "\n").encode("utf-8"))
            f.flush()
        except Exception as e:
            print(f"[infer] conn error: {e}", flush=True)
        finally:
            conn.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8850)
    ap.add_argument("--model-path", default="./pretrained_models/VoxCPM2")
    ap.add_argument("--device", default="mps")
    ap.add_argument("--base-dir", default=".")
    args = ap.parse_args()
    base = Path(args.base_dir).resolve()
    serve(args.port, args.model_path, args.device, base)


if __name__ == "__main__":
    main()
