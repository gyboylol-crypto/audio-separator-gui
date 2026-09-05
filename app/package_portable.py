"""Create a new ZIP64 bundle, excluding caches and nonportable installer artifacts."""
from __future__ import annotations
import argparse
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def bundle(output: Path, source_only: bool = False):
    skip = {".git", ".cache", "__pycache__", ".pytest_cache", "dist", "downloads", "uv-cache", "managed-python"}
    count = total = 0
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=1, allowZip64=True) as archive:
        for path in ROOT.rglob("*"):
            relative = path.relative_to(ROOT)
            if any(part in skip for part in relative.parts):
                continue
            if source_only and relative.parts[0] in (".runtime", ".models"):
                continue
            if source_only and relative.name in ("CHECKPOINT.md", "VERIFICATION.md", "VERIFICATION_V2.md"):
                continue
            if path.is_symlink() or path.is_junction():
                raise RuntimeError(f"不打包链接路径：{relative}")
            if not path.is_file() or path.resolve() == output.resolve():
                continue
            if path.name == "pyvenv.cfg":
                raise RuntimeError(f"存在不可移动的虚拟环境配置：{relative}")
            # Console entry points copied from pip/venv embed absolute prefixes;
            # the GUI only uses python.exe and Python modules directly.
            if relative.parts[0] == ".runtime" and "Scripts" in relative.parts:
                continue
            archive.write(path, "audio-separator-gui/" + relative.as_posix())
            count += 1
            total += path.stat().st_size
            if count % 2000 == 0:
                print(f"已打包 {count} 个文件，原始大小 {total / 1024**3:.2f} GiB", flush=True)
    print(f"打包完成：{output}；{count} 文件；原始大小 {total / 1024**3:.2f} GiB", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    bundle(args.output.resolve(), args.source_only)
