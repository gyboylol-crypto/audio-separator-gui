"""Isolated ClearVoice adapter; never produces a subtraction/background stem."""
from __future__ import annotations

import argparse
import os
from pathlib import Path


def create_engine(model_dir: Path):
    from clearvoice.network_wrapper import network_wrapper
    from clearvoice.networks import CLS_MossFormer2_SE_48K

    config = network_wrapper()
    config.model_name = "MossFormer2_SE_48K"
    config.load_args_se()
    config.args.task = "speech_enhancement"
    config.args.network = config.model_name
    checkpoint_dir = model_dir / config.model_name
    marker = checkpoint_dir / "last_best_checkpoint"
    if not marker.is_file():
        raise FileNotFoundError("缺少 Moss 模型，请先运行部署模型入口")
    checkpoint = (checkpoint_dir / marker.read_text(encoding="utf-8").strip()).resolve()
    if not checkpoint.is_relative_to(checkpoint_dir.resolve()) or not checkpoint.is_file():
        raise FileNotFoundError("Moss 模型文件不完整或路径无效，请重新部署")
    config.args.checkpoint_dir = str(checkpoint_dir.resolve())
    return CLS_MossFormer2_SE_48K(config.args)


def enhance(source: Path, output: Path, model_dir: Path):
    import numpy as np
    import soundfile as sf

    engine = create_engine(model_dir)
    enhanced = np.asarray(engine.process(str(source), online_write=False), dtype=np.float32)
    original = sf.info(str(source))
    # ClearVoice 0.1.2 returns channel-first arrays, including mono (1, N).
    if enhanced.ndim == 2 and enhanced.shape[0] == original.channels:
        enhanced = enhanced.T
    if enhanced.ndim == 1:
        enhanced = enhanced[:, None]
    if enhanced.ndim != 2 or enhanced.shape[1] != original.channels:
        raise RuntimeError(f"降噪结果声道异常：{enhanced.shape}，原声道 {original.channels}")
    if abs(len(enhanced) - original.frames) > int(original.samplerate * 0.02):
        raise RuntimeError("降噪结果长度异常，未写出缺段音频")
    if not np.isfinite(enhanced).all():
        raise RuntimeError("降噪结果包含无效数值")
    # Correct only sub-frame rounding, not missing audio segments.
    enhanced = enhanced[:original.frames]
    if len(enhanced) < original.frames:
        enhanced = np.pad(enhanced, ((0, original.frames - len(enhanced)), (0, 0)))
    sf.write(str(output), np.clip(enhanced, -1, 1), original.samplerate, subtype="PCM_16")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model-dir", type=Path, required=True)
    args = parser.parse_args()
    os.environ["HF_HUB_OFFLINE"] = "1"
    enhance(args.input, args.output, args.model_dir)
