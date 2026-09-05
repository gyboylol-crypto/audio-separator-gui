# 验收范围

版本：v2.0.0，Windows 10 x64 / NVIDIA RTX 4060。

- 三模型分别通过中文、空格、方括号、& 文件名的 MP3/MP4 双文件批处理。
- MDX23C 与 BS-RoFormer 输出两条音轨；MossFormer2 仅输出一条降噪音频。
- 输出经过源文件时长校验，输入文件 SHA-256 保持不变，重名输出自动编号。
- 完整运行文件经 ZIP64 压缩，解压到另一盘符的中文特殊字符路径后，两个独立 Python 环境和三模型批处理再次通过。
- 12 项 Python 单元测试通过。
- Windows PowerShell 5.1 测试通过：UTF-8 半字符日志、CR 进度刷新、分块切换、合并状态、完成状态保护。
- 30 秒 BS 实际推理测试在结束前捕获多次进度变化，最终成功。

## 复现测试

安装完成后，在项目目录打开 PowerShell：

```powershell
.\.runtime\python\python.exe -X utf8 -m unittest discover -s tests -v
```

`tests/test_events.ps1`、`tests/test_bs_live_progress.ps1` 接受显式测试目录；真实推理测试还需要测试音频。请使用有权处理的素材，并把测试输出放入独立目录。

这些测试不代表所有电脑和所有音频均适用。未进行跨实体电脑的兼容性测试，也不保证每种 FPS 音效的人声分离质量。CPU 可回退但未做性能承诺。清洁机器的完整首次安装流程尚未端到端验收；公开首版应先用短片段确认效果。
