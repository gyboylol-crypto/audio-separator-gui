"""Explicit model download entry point. Inference can then run offline."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
os.environ["HF_HOME"] = str(ROOT / ".cache" / "huggingface")
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["PATH"] = str(ROOT / ".runtime" / "ffmpeg") + os.pathsep + os.environ.get("PATH", "")


def deploy(which: str):
    model_dir = ROOT / ".models"
    model_dir.mkdir(exist_ok=True)
    if which in ("all", "separation"):
        from audio_separator.separator import Separator
        separator = Separator(model_file_dir=str(model_dir), output_dir=str(ROOT / ".cache"))
        for name in ("MDX23C-8KFFT-InstVoc_HQ.ckpt", "model_bs_roformer_ep_317_sdr_12.9755.ckpt"):
            print(f"部署 {name}", flush=True)
            separator.download_model_and_data(name)
    if which in ("all", "moss"):
        if Path(sys.executable).parent.name != "moss-python":
            subprocess.run([str(ROOT / ".runtime" / "moss-python" / "python.exe"),
                            "-X", "utf8", str(Path(__file__).resolve()), "--only", "moss"], check=True)
        else:
            from huggingface_hub import hf_hub_download
            for name in ("last_best_checkpoint", "last_best_checkpoint.pt", "README.md"):
                hf_hub_download("alibabasglab/MossFormer2_SE_48K", name,
                                revision="eff8c97925c8bec812af707814b3e5d777fd4503",
                                local_dir=str(model_dir / "MossFormer2_SE_48K"))
    entries = []
    for path in sorted(model_dir.rglob("*")):
        if path.is_file() and ".cache" not in path.parts and path.name != "deployment-manifest.json":
            with path.open("rb") as handle:
                digest = hashlib.file_digest(handle, "sha256").hexdigest()
            entries.append({"path": path.relative_to(model_dir).as_posix(), "bytes": path.stat().st_size, "sha256": digest})
    (model_dir / "deployment-manifest.json").write_text(json.dumps(entries, ensure_ascii=False, indent=2), encoding="utf-8")
    print("模型下载完成；实际可用性仍需推理验收。", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=["all", "separation", "moss"], default="all")
    deploy(parser.parse_args().only)
