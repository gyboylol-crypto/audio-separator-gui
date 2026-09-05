import json
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "app"))
import worker


class WorkerTests(unittest.TestCase):
    def test_moss_exports_only_denoised_and_preserves_original(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "中文 录音[01]&测试.wav"
            source.write_bytes(b"original")
            def enhance(_source, work, _models):
                result = work / "denoised.wav"
                result.write_bytes(b"enhanced")
                return result
            with patch.dict(worker.os.environ, {"AUDIO_SEPARATOR_TEMP": directory}), \
                 patch.object(worker, "separate_clearvoice", side_effect=enhance), \
                 patch.object(worker, "validate_output_durations") as validate:
                outputs = worker.process_one(source, {"engine": "clearvoice"}, Path(directory))
            self.assertEqual(len(outputs), 1)
            self.assertEqual(outputs[0].name, "中文 录音[01]&测试_Denoised.wav")
            self.assertEqual(outputs[0].read_bytes(), b"enhanced")
            self.assertEqual(source.read_bytes(), b"original")
            self.assertFalse(list(Path(directory).glob("*Background*")))
            validate.assert_called_once()

    def test_exclusive_copy_preserves_concurrently_created_file(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory) / "in", Path(directory) / "out"
            source.write_bytes(b"new")
            target.write_bytes(b"existing")
            with self.assertRaises(FileExistsError):
                worker.copy_exclusive(source, target)
            self.assertEqual(target.read_bytes(), b"existing")

    def test_event_file_is_utf8_json_with_single_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "中文事件.jsonl"
            with patch.object(worker, "EVENT_FILE", path):
                worker.emit("file_completed", outputs=["中文目录/降噪.wav"])
            data = json.loads(path.read_bytes().decode("utf-8"))
            self.assertEqual(data["outputs"], ["中文目录/降噪.wav"])

    def test_model_registry_contains_required_models(self):
        models = {item["id"]: item for item in worker.load_models()}
        self.assertEqual(models["mdx23c_8kfft_instvoc_hq"]["engine"], "audio_separator")
        self.assertEqual(models["bs_roformer_viperx_1297"]["engine"], "audio_separator")
        self.assertEqual(models["mossformer2_se_48k"]["engine"], "clearvoice")

    def test_validate_inputs_rejects_unknown_extension(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.txt"
            path.write_text("x", encoding="utf-8")
            with self.assertRaises(ValueError):
                worker.validate_inputs([str(path)])

    def test_validate_inputs_accepts_mp3_and_mp4_and_deduplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            mp3 = Path(directory) / "a.mp3"
            mp4 = Path(directory) / "b.mp4"
            mp3.touch()
            mp4.touch()
            result = worker.validate_inputs([str(mp3), str(mp4), str(mp3)])
            self.assertEqual(result, [mp3.resolve(), mp4.resolve()])

    def test_unique_output_path_never_overwrites(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "clip.mp3"
            source.touch()
            first = Path(directory) / "clip_Vocals.wav"
            second = Path(directory) / "clip_Vocals_2.wav"
            first.touch()
            second.touch()
            self.assertEqual(worker.unique_output_path(source, "Vocals").name, "clip_Vocals_3.wav")

    def test_unique_output_pair_uses_the_same_suffix_for_both_stems(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "clip.mp3"
            source.touch()
            (Path(directory) / "clip_Vocals.wav").touch()
            vocals, background = worker.unique_output_pair(source)
            self.assertEqual(vocals.name, "clip_Vocals_2.wav")
            self.assertEqual(background.name, "clip_Background_2.wav")

    def test_classify_outputs(self):
        vocals = Path("clip_(Vocals)_model.wav")
        instrumental = Path("clip_(Instrumental)_model.wav")
        self.assertEqual(worker.classify_outputs([instrumental, vocals]), (vocals, instrumental))

    def test_configure_process_environment_prepends_bundled_ffmpeg(self):
        original = worker.os.environ.get("PATH", "")
        original_finder = worker.find_ffmpeg
        original_probe_finder = worker.find_ffprobe
        try:
            worker.find_ffmpeg = lambda: Path(r"C:\project\.runtime\ffmpeg\ffmpeg.exe")
            worker.find_ffprobe = lambda: Path(r"C:\project\.runtime\ffmpeg\ffprobe.exe")
            worker.os.environ["PATH"] = r"C:\Windows\System32"
            worker.configure_process_environment()
            self.assertTrue(worker.os.environ["PATH"].startswith(r"C:\project\.runtime\ffmpeg"))
        finally:
            worker.find_ffmpeg = original_finder
            worker.find_ffprobe = original_probe_finder
            worker.os.environ["PATH"] = original

    def test_validate_output_durations_accepts_small_rounding_difference(self):
        original_probe = worker.media_duration_seconds
        durations = {"source.mp3": 600.0, "vocals.wav": 599.8, "background.wav": 599.8}
        try:
            worker.media_duration_seconds = lambda path: durations[path.name]
            worker.validate_output_durations(
                Path("source.mp3"),
                (Path("vocals.wav"), Path("background.wav")),
            )
        finally:
            worker.media_duration_seconds = original_probe

    def test_validate_output_durations_rejects_truncated_result(self):
        original_probe = worker.media_duration_seconds
        durations = {"source.mp3": 600.0, "vocals.wav": 587.7, "background.wav": 587.7}
        try:
            worker.media_duration_seconds = lambda path: durations[path.name]
            with self.assertRaisesRegex(RuntimeError, "时长异常"):
                worker.validate_output_durations(
                    Path("source.mp3"),
                    (Path("vocals.wav"), Path("background.wav")),
                )
        finally:
            worker.media_duration_seconds = original_probe


if __name__ == "__main__":
    unittest.main()
