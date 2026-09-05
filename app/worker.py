from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import traceback
import uuid
from pathlib import Path
from typing import Any, Iterable


APP_ROOT = Path(__file__).resolve().parents[1]
MODEL_CONFIG = APP_ROOT / "app" / "models.json"
DEFAULT_MODEL_DIR = APP_ROOT / ".models"
VIDEO_EXTENSIONS = {".mp4", ".mkv", ".mov", ".webm", ".avi"}
AUDIO_EXTENSIONS = {".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg", ".wma", ".opus"}
SUPPORTED_EXTENSIONS = VIDEO_EXTENSIONS | AUDIO_EXTENSIONS
EVENT_FILE: Path | None = None


def emit(event_type: str, **payload: Any) -> None:
    message = {"type": event_type, **payload}
    line = json.dumps(message, ensure_ascii=False)
    if EVENT_FILE is not None:
        with EVENT_FILE.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(line + "\n")
    else:
        print(line, flush=True)


def load_models(path: Path = MODEL_CONFIG) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, list):
        raise ValueError("models.json 必须是数组")
    return data


def model_by_id(model_id: str) -> dict[str, Any]:
    for model in load_models():
        if model.get("id") == model_id and model.get("enabled", True):
            return model
    raise ValueError(f"未知或未启用的模型：{model_id}")


def validate_inputs(paths: Iterable[str]) -> list[Path]:
    result: list[Path] = []
    seen: set[str] = set()
    for raw in paths:
        path = Path(raw).expanduser().resolve()
        key = os.path.normcase(str(path))
        if key in seen:
            continue
        if not path.is_file():
            raise FileNotFoundError(f"文件不存在：{path}")
        if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
            raise ValueError(f"不支持的格式：{path.suffix}（{path.name}）")
        seen.add(key)
        result.append(path)
    if not result:
        raise ValueError("没有可处理的文件")
    return result


def unique_output_path(source: Path, label: str, extension: str = ".wav") -> Path:
    candidate = source.with_name(f"{source.stem}_{label}{extension}")
    counter = 2
    while candidate.exists():
        candidate = source.with_name(f"{source.stem}_{label}_{counter}{extension}")
        counter += 1
    return candidate


def unique_output_pair(source: Path, extension: str = ".wav") -> tuple[Path, Path]:
    """Choose one collision suffix for both output stems."""
    counter = 1
    while True:
        suffix = "" if counter == 1 else f"_{counter}"
        vocals = source.with_name(f"{source.stem}_Vocals{suffix}{extension}")
        background = source.with_name(f"{source.stem}_Background{suffix}{extension}")
        if not vocals.exists() and not background.exists():
            return vocals, background
        counter += 1


def find_ffmpeg() -> Path:
    candidates = [
        APP_ROOT / ".runtime" / "ffmpeg" / "ffmpeg.exe",
        Path(os.environ.get("AUDIO_SEPARATOR_FFMPEG", "")),
    ]
    system_ffmpeg = shutil.which("ffmpeg")
    if system_ffmpeg:
        candidates.append(Path(system_ffmpeg))
    for candidate in candidates:
        if str(candidate) and candidate.is_file():
            return candidate
    raise FileNotFoundError("未找到 ffmpeg.exe，请先运行 setup.ps1")


def find_ffprobe() -> Path:
    candidates = [
        APP_ROOT / ".runtime" / "ffmpeg" / "ffprobe.exe",
        Path(os.environ.get("AUDIO_SEPARATOR_FFPROBE", "")),
    ]
    system_ffprobe = shutil.which("ffprobe")
    if system_ffprobe:
        candidates.append(Path(system_ffprobe))
    for candidate in candidates:
        if str(candidate) and candidate.is_file():
            return candidate
    raise FileNotFoundError("未找到 ffprobe.exe；超过 10 分钟的音频需要它来分块，请重新运行 setup.cmd")


def configure_process_environment() -> None:
    os.environ["PYTHONUTF8"] = "1"
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["HF_HOME"] = str(APP_ROOT / ".cache" / "huggingface")
    os.environ["TORCH_HOME"] = str(APP_ROOT / ".cache" / "torch")
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    tool_dirs = [str(find_ffmpeg().parent), str(find_ffprobe().parent)]
    path_parts = os.environ.get("PATH", "").split(os.pathsep)
    for tool_dir in reversed(list(dict.fromkeys(tool_dirs))):
        if tool_dir not in path_parts:
            os.environ["PATH"] = tool_dir + os.pathsep + os.environ.get("PATH", "")
            path_parts.insert(0, tool_dir)


def run_ffmpeg(arguments: list[str]) -> None:
    ffmpeg = find_ffmpeg()
    process = subprocess.run(
        [str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y", *arguments],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    if process.returncode != 0:
        raise RuntimeError(process.stderr.strip() or "FFmpeg 执行失败")


def prepare_audio(source: Path, work_dir: Path, force_wav: bool = False, sample_rate: int = 48000) -> Path:
    if source.suffix.lower() not in VIDEO_EXTENSIONS and not force_wav:
        return source
    target = work_dir / "input.wav"
    run_ffmpeg(["-i", str(source), "-vn", "-acodec", "pcm_s16le", "-ar", str(sample_rate), str(target)])
    return target


def media_duration_seconds(path: Path) -> float:
    ffprobe = find_ffprobe()
    process = subprocess.run(
        [
            str(ffprobe),
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    if process.returncode != 0:
        raise RuntimeError(process.stderr.strip() or f"无法读取音频时长：{path}")
    try:
        duration = float(process.stdout.strip())
    except ValueError as exc:
        raise RuntimeError(f"FFprobe 返回了无效时长：{path}") from exc
    if duration <= 0:
        raise RuntimeError(f"音频时长无效：{path}")
    return duration


def validate_output_durations(source: Path, outputs: Iterable[Path]) -> None:
    source_duration = media_duration_seconds(source)
    tolerance = max(0.5, source_duration * 0.001)
    for output in outputs:
        output_duration = media_duration_seconds(output)
        difference = abs(source_duration - output_duration)
        emit(
            "engine_log",
            message=(
                f"时长校验：{output.name} {output_duration:.3f} 秒；"
                f"原文件 {source_duration:.3f} 秒；差值 {difference:.3f} 秒。"
            ),
        )
        if difference > tolerance:
            raise RuntimeError(
                f"分离结果时长异常：{output.name} 比原文件相差 {difference:.3f} 秒，"
                "已停止复制结果，避免生成缺段文件"
            )


def classify_outputs(paths: Iterable[Path]) -> tuple[Path, Path]:
    outputs = [Path(path) for path in paths]
    vocals = next((p for p in outputs if "vocal" in p.name.lower()), None)
    background = next(
        (p for p in outputs if any(token in p.name.lower() for token in ("instrumental", "other", "no_vocal"))),
        None,
    )
    if vocals is None or background is None:
        names = ", ".join(path.name for path in outputs)
        raise RuntimeError(f"无法识别分离结果中的人声/背景轨：{names}")
    return vocals, background


def resolve_generated_path(raw: str | Path, work_dir: Path) -> Path:
    path = Path(raw)
    if not path.is_absolute():
        path = work_dir / path
    return path.resolve()


def separate_audio_separator(source: Path, model: dict[str, Any], work_dir: Path, model_dir: Path) -> tuple[Path, Path]:
    try:
        from audio_separator.separator import Separator
    except ImportError as exc:
        raise RuntimeError("audio-separator 尚未安装，请先运行 setup.ps1") from exc

    capture = io.StringIO()
    with contextlib.redirect_stdout(capture):
        separator = Separator(
            model_file_dir=str(model_dir),
            output_dir=str(work_dir),
            output_format="WAV",
            use_autocast=True,
            chunk_duration=600,
        )
        separator.load_model(model_filename=model["model_filename"])
        raw_outputs = separator.separate(str(source))
    for line in capture.getvalue().splitlines():
        if line.strip():
            emit("engine_log", message=line.strip())
    outputs = [resolve_generated_path(path, work_dir) for path in raw_outputs]
    for output in outputs:
        if not output.is_file():
            raise RuntimeError(f"分离引擎报告了不存在的输出：{output}")
    return classify_outputs(outputs)


def normalize_clearvoice_output(value: Any) -> Any:
    if isinstance(value, (list, tuple)) and len(value) == 1:
        return normalize_clearvoice_output(value[0])
    if isinstance(value, dict):
        for key in ("audio", "wav", "output", "waveform"):
            if key in value:
                return normalize_clearvoice_output(value[key])
    return value


def separate_clearvoice(source: Path, work_dir: Path, model_dir: Path) -> Path:
    python = APP_ROOT / ".runtime" / "moss-python" / "python.exe"
    if not python.is_file():
        raise RuntimeError("缺少 Moss 运行环境，请运行 setup-mossformer.ps1")
    prepared = prepare_audio(source, work_dir, force_wav=True, sample_rate=48000)
    output = work_dir / "denoised.wav"
    result = subprocess.run(
        [str(python), "-I", "-X", "utf8", str(APP_ROOT / "app" / "moss_backend.py"),
         "--input", str(prepared), "--output", str(output), "--model-dir", str(model_dir)],
        cwd=str(APP_ROOT), stdout=sys.stderr, stderr=sys.stderr,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    if result.returncode or not output.is_file():
        raise RuntimeError(f"Moss 降噪失败（退出码 {result.returncode}），请查看引擎日志")
    return output


def copy_exclusive(source: Path, target: Path) -> None:
    # Exclusive creation also protects files created concurrently after naming.
    with target.open("xb") as output, source.open("rb") as input_file:
        shutil.copyfileobj(input_file, output)


def copy_results(source: Path, vocals: Path, background: Path) -> tuple[Path, Path]:
    vocals_target, background_target = unique_output_pair(source)
    copy_exclusive(vocals, vocals_target)
    copy_exclusive(background, background_target)
    return vocals_target, background_target


def process_one(source: Path, model: dict[str, Any], model_dir: Path) -> tuple[Path, ...]:
    base_temp = Path(os.environ.get("AUDIO_SEPARATOR_TEMP", str(APP_ROOT / ".cache" / "jobs")))
    base_temp.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="local-audio-separator-", dir=base_temp) as raw_work_dir:
        work_dir = Path(raw_work_dir)
        engine = model["engine"]
        if engine == "audio_separator":
            # audio-separator keeps the input extension when it creates long-file
            # chunks. Some FFmpeg/MP3 combinations shorten those intermediate
            # files, so feed it lossless WAV at the model's native sample rate.
            prepared = prepare_audio(
                source,
                work_dir,
                force_wav=True,
                sample_rate=int(model.get("sample_rate", 44100)),
            )
            vocals, background = separate_audio_separator(prepared, model, work_dir, model_dir)
        elif engine == "clearvoice":
            enhanced = separate_clearvoice(source, work_dir, model_dir)
            validate_output_durations(source, (enhanced,))
            target = unique_output_path(source, "Denoised")
            copy_exclusive(enhanced, target)
            return (target,)
        else:
            raise ValueError(f"不支持的引擎：{engine}")
        validate_output_durations(source, (vocals, background))
        return copy_results(source, vocals, background)


def run_batch(paths: list[str], model_id: str, model_dir: Path) -> int:
    configure_process_environment()
    files = validate_inputs(paths)
    model = model_by_id(model_id)
    model_dir.mkdir(parents=True, exist_ok=True)
    emit("batch_started", total=len(files), model=model["name"])
    succeeded = 0
    failed = 0
    for index, source in enumerate(files, start=1):
        emit("file_started", index=index, total=len(files), path=str(source))
        try:
            outputs = process_one(source, model, model_dir)
        except Exception as exc:  # keep the remaining batch running
            failed += 1
            emit(
                "file_failed",
                index=index,
                path=str(source),
                error=str(exc),
                detail=traceback.format_exc(),
            )
        else:
            succeeded += 1
            emit(
                "file_completed",
                index=index,
                path=str(source),
                outputs=[str(path) for path in outputs],
                mode="denoise" if model["engine"] == "clearvoice" else "separate",
            )
    emit("batch_completed", succeeded=succeeded, failed=failed, total=len(files))
    return 0 if failed == 0 else 2


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="本地音频分离 GUI 的后台工作进程")
    parser.add_argument("--model", help="models.json 中的模型 ID")
    parser.add_argument("--job", type=Path, help="UTF-8 JSON 任务文件（供界面使用）")
    parser.add_argument("--model-dir", default=str(DEFAULT_MODEL_DIR))
    parser.add_argument("files", nargs="*")
    return parser


def main() -> int:
    global EVENT_FILE
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    args = build_parser().parse_args()
    try:
        if args.job:
            job = json.loads(args.job.read_text(encoding="utf-8-sig"))
            args.files, args.model = job["files"], job["model"]
            args.model_dir = job.get("model_dir", args.model_dir)
            EVENT_FILE = Path(job["events"])
            # Own UTF-8 files avoid PowerShell's redirected-stream transcoding.
            log = open(job["engine_log"], "a", encoding="utf-8", buffering=1)
            sys.stdout = sys.stderr = log
        return run_batch(args.files, args.model, Path(args.model_dir).resolve())
    except Exception as exc:
        emit("fatal", error=str(exc), detail=traceback.format_exc())
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
