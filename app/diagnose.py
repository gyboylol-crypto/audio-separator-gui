"""Read-only checks. No downloads, installs, registry edits, or system changes."""
from __future__ import annotations
import argparse
import json
import os
import platform
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def child(engine):
    import importlib.metadata as metadata
    import torch
    if engine == "python":
        import audio_separator
        packages = ["audio-separator", "torch", "numpy"]
    else:
        import clearvoice
        from clearvoice.networks import CLS_MossFormer2_SE_48K
        packages = ["clearvoice", "torch", "torchaudio", "numpy"]
    cuda = torch.cuda.is_available()
    if cuda:
        (torch.ones(8, device="cuda") * 2).sum().item()
    external = [path for path in sys.path if path and not Path(path).resolve().is_relative_to(ROOT)]
    if external:
        raise RuntimeError(f"Python 搜索路径包含项目外部位置：{external}")
    return {"executable": sys.executable, "prefix": sys.prefix,
            "packages": {name: metadata.version(name) for name in packages},
            "device": torch.cuda.get_device_name(0) if cuda else "CPU（可运行，但处理较慢；需要 GPU 加速请更新 NVIDIA 驱动）",
            "external_python_paths": external}


def diagnose():
    print("检查目录：", ROOT, flush=True)
    failures = 0
    if platform.system() != "Windows" or platform.machine().upper() not in ("AMD64", "X86_64"):
        print("此完整运行包仅适用于 Windows x64。")
        failures += 1
    for engine in ("python", "moss-python"):
        interpreter = ROOT / ".runtime" / engine / "python.exe"
        if not interpreter.is_file():
            print(f"缺少 {engine}；请运行 setup.cmd。")
            failures += 1
            continue
        if (interpreter.parent / "pyvenv.cfg").exists():
            print(f"{engine} 仍是可能依赖固定路径的 venv。")
            failures += 1
        result = subprocess.run([str(interpreter), "-I", "-X", "utf8", str(Path(__file__).resolve()), "--child", engine],
                                capture_output=True, encoding="utf-8", errors="replace")
        print(result.stdout or result.stderr)
        if result.returncode:
            failures += 1
            print("环境加载失败：若提示 DLL/VCRUNTIME/MSVCP 缺失，请安装 Microsoft Visual C++ 2015–2022 x64 运行库。")
            print("若提示 CUDA 驱动错误，请更新 NVIDIA 驱动；本程序不要求安装 DX12 或系统 Python。")
    for name in ("ffmpeg.exe", "ffprobe.exe"):
        path = ROOT / ".runtime" / "ffmpeg" / name
        try:
            result = subprocess.run([str(path), "-version"], capture_output=True, encoding="utf-8", errors="replace")
            print(result.stdout.splitlines()[0] if result.stdout else result.stderr)
            failures += int(result.returncode != 0)
        except OSError as exc:
            print(f"{name} 不可用：{exc}；请运行 setup.cmd。")
            failures += 1
    for name in ("MDX23C-8KFFT-InstVoc_HQ.ckpt", "model_bs_roformer_ep_317_sdr_12.9755.ckpt", "MossFormer2_SE_48K/last_best_checkpoint.pt"):
        path = ROOT / ".models" / name
        exists = path.is_file() and path.stat().st_size > 1024
        print(f"模型 {'存在' if exists else '缺失'}：{name}")
        failures += int(not exists)
    print(f"检查完成：{failures} 项失败。此检查不代替真实音频推理验收。")
    return int(failures > 0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--child", choices=["python", "moss-python"])
    args = parser.parse_args()
    if args.child:
        print(json.dumps(child(args.child), ensure_ascii=False))
    else:
        raise SystemExit(diagnose())
