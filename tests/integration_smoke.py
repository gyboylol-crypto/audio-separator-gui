"""Real two-file batches, using the same UTF-8 job protocol as the GUI."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run(source: Path, work: Path):
    work.mkdir(parents=True, exist_ok=False)
    ffmpeg = ROOT / ".runtime" / "ffmpeg" / "ffmpeg.exe"
    ffprobe = ROOT / ".runtime" / "ffmpeg" / "ffprobe.exe"
    files = [work / "中文 空格[一]&录音.mp3", work / "中文 视频[二]&录音.mp4"]
    for file in files:
        subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-n", "-i", str(source),
                        "-t", "12", "-vn", str(file)], check=True)
    hashes = {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
    results = []
    for model in ("mdx23c_8kfft_instvoc_hq", "bs_roformer_viperx_1297", "mossformer2_se_48k"):
        job = {"model": model, "files": [str(f) for f in files],
               "events": str(work / (model + ".jsonl")), "engine_log": str(work / (model + ".log"))}
        job_path = work / (model + ".json")
        job_path.write_text(json.dumps(job, ensure_ascii=False), encoding="utf-8")
        env = os.environ.copy()
        env["AUDIO_SEPARATOR_TEMP"] = str(work)
        env["HF_HUB_OFFLINE"] = "1"
        env["PYTHONPATH"] = "Z:\\intentionally-invalid"
        child = subprocess.run([sys.executable, "-I", "-X", "utf8", str(ROOT / "app" / "worker.py"), "--job", str(job_path)],
                               cwd=str(work), env=env)
        events = [json.loads(line) for line in Path(job["events"]).read_text(encoding="utf-8").splitlines()]
        assert child.returncode == 0, (model, events)
        completed = [e for e in events if e["type"] == "file_completed"]
        assert len(completed) == 2, events
        expected = 1 if model.startswith("moss") else 2
        for event in completed:
            assert len(event["outputs"]) == expected, event
            for output in event["outputs"]:
                info = subprocess.check_output([str(ffprobe), "-v", "error", "-show_entries", "format=duration", "-of", "json", output], encoding="utf-8")
                assert abs(float(json.loads(info)["format"]["duration"]) - 12) < 0.1, output
        results.append({"model": model, "batch_files": 2, "output_count_per_file": expected, "status": "passed"})
        print(json.dumps(results[-1], ensure_ascii=False), flush=True)
    for file in files:
        assert hashlib.sha256(file.read_bytes()).hexdigest() == hashes[str(file)], "source changed"
    report = {"root": str(ROOT), "work": str(work), "results": results, "source_sha256_unchanged": True}
    (work / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("所有真实双文件批处理通过，原文件哈希未变。", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    run(args.source, args.work)
