# 本地音频分离器

> 专为快速分离人声与背景音打造。不堆砌复杂功能，无需研究繁琐参数：首次完成安装后，拖入音频、选择模型、一键分离，支持批量处理。让创作者把时间留给内容，而不是软件操作。

Windows x64 本地音频工具 v2：人声/背景分离，或语音降噪增强。原文件只读，结果默认写入原文件所在目录。旧版目录不参与 v2 运行。

适合自媒体、游戏视频和口播创作者：拖入素材，选择模型，批量处理。本项目提供图形界面和工作流程，分离/降噪算法来自下方列出的第三方开源项目，并非自行训练。

## 下载与开始使用

**本仓库发布的是源码 + 一键安装入口，不含离线运行环境和模型。首次安装需要联网下载数 GB 文件，建议预留至少 25 GB 磁盘空间。**

1. 点击仓库绿色 **Code → Download ZIP**，将压缩包完整解压到一个有写入权限的目录。
2. 双击 `setup.cmd`，等待 Python、FFmpeg、依赖和三个模型安装完成。无需提前安装 Python 或 UVR，也不需要管理员运行。
3. 双击 `启动音频分离器.cmd`，拖入音频/视频或添加文件夹。
4. 选择模型，点击“开始分离”或“开始降噪”。结果自动保存在原文件旁边。

首次安装需要访问 GitHub、PyPI、PyTorch 下载站、Hugging Face 和 Gyan。网络受限时可能下载失败；请保留报错，网络恢复后重新运行安装入口。已安装完成后的音频推理在本机进行。

| 模型 | 用途 | 输出 |
| --- | --- | --- |
| MDX23C 8K FFT | 人声与背景分离，默认选项 | Vocals + Background |
| BS-RoFormer Viperx 1297 | 另一种人声/背景分离方案，可对比试听；本机测试较慢 | Vocals + Background |
| MossFormer2 SE 48K | 说话声降噪增强，可能抑制游戏音效 | 仅 Denoised |

长文件需要等待。进度条显示**当前计算分块**，进入下一块会从 0% 重新开始；模型准备和音轨合并阶段显示活动指示。速度取决于模型、硬件和音频时长，不保证实时处理。

需要帮助请提交 [Issue](https://github.com/gyboylol-crypto/audio-separator-gui/issues)，说明系统、显卡、模型、音频时长和报错。不要公开上传未经授权的原始音频；粘贴日志前请隐去用户名和私人文件路径。

## 已支持

- 图形界面：添加/拖放文件、添加文件夹、移除、批量处理、取消任务、日志和进度。
- 输入：MP3、MP4、WAV、FLAC、M4A、AAC、OGG、WMA、OPUS、MKV、MOV、WEBM、AVI。
- MDX23C / BS-RoFormer 输出：`原名_Vocals.wav` 与 `原名_Background.wav`。
- MossFormer2 SE 48K 输出：仅 `原名_Denoised.wav`，不再通过相减生成背景轨。
- 重名自动追加数字，不覆盖已有文件。模型名括号内显示用途；空列表显示浅灰色拖放提示。
- MP4 等视频会使用 FFmpeg 自动提取音轨。
- MDX/BS 长音频按 10 分钟分块，Moss 使用自身分段推理。程序未设置总时长限制，但仍受内存、磁盘空间等约束。输入会先转成模型原生采样率的无损 WAV，避免有损中间文件丢失时长。
- 每条输出在复制到原文件旁边前都会和原文件做时长校验，异常结果不会被当成成功文件。

## 当前验证状态

- MDX23C、BS-RoFormer Viperx 1297、MossFormer2 SE 48K：已部署，在 RTX 4060 上通过中文特殊字符文件名的 MP3/MP4 双文件批处理实测。
- Moss 另通过 24 秒立体声片段的单文件降噪及输出时长校验。
- 这些是功能验收，不代表每种 FPS 素材都能获得理想音质。请先试听片段，Moss 可能削弱游戏音效，不适合以保留全部环境音为目的的处理。

FPS 游戏中的枪声、脚步、技能音效会与语音频段重叠，任何单一模型都不能保证在所有素材上最优；正式生产前建议拿真实游戏片段做 A/B 听评。

## 首次使用

1. **完整运行包**：保留 `.runtime`、`.models` 和 `app` 等内容，解压后双击 `启动音频分离器.cmd`。已经配好环境的完整包不需要重新安装。
2. **Git 源码包**：先运行 `setup.cmd` 联网下载 Python、依赖和三个模型，完成后再启动。仅源码不能解压即用。
3. 拖入文件，选择模型，点击“开始分离”或“开始降噪”。结果放在源文件旁，原文件保留。
4. 有问题先运行 `环境检查.cmd`。Moss 单独修复入口为 `安装MossFormer2支持.cmd`，模型下载入口为 `部署模型.cmd`。

## 移动、打包与外部依赖

- 可以关闭程序后，将整个文件夹压缩、移动或改名。不要仅复制启动脚本，也不要漏掉以点开头的目录。
- 两个 Python 环境各自独立：`.runtime/python/python.exe` 用于 MDX/BS，`.runtime/moss-python/python.exe` 用于 Moss；不使用带绝对 `home` 的 venv。
- 本地模型位于 `.models`，运行日志与缓存位于 `.cache`。不依赖系统 Python、UVR 安装位置或原版目录，不修改全局 PATH。
- 完整包面向 Windows x64。GPU 加速需要兼容的 NVIDIA 驱动；未发现可用 CUDA 时使用 CPU，速度会慢。无需另装 CUDA Toolkit 或 DX12。
- 若 Python/Torch 提示 VCRUNTIME/MSVCP/DLL 缺失，请安装微软 Visual C++ 2015–2022 x64 运行库。驱动和系统运行库不由本程序安装。
- 使用自带 Python 执行 `app/package_portable.py --output <新压缩包路径>` 可生成 ZIP64 完整包；加 `--source-only` 生成不含环境、模型与缓存的源码包。目标必须不存在。
- 当前公开版本仅提供源码和安装入口。分发含模型和 FFmpeg 的完整包前应核对第三方许可证，详见 `THIRD_PARTY_NOTICES.md`。

## 数据与安全边界

- 所有推理均在本机执行，音视频不会上传。
- 原文件从不修改、移动或删除。
- 模型权重可能体积较大；只应使用可信来源。项目内置名称由 `audio-separator` 或 ClearVoice 的官方模型列表解析。
- 模型、运行环境和缓存目录不纳入源码版本控制。
- 本机使用与对外打包的许可边界不同；详情见 `THIRD_PARTY_NOTICES.md`。

## 已执行的验收

公开验收范围见 `TESTING.md`。已在 Windows 10 x64 / RTX 4060 上测试，不代表所有硬件均经过验收。

## 许可证与致谢

本项目自有代码按 [MIT License](LICENSE) 发布。第三方代码、运行库及模型保留其各自许可证，MIT 不替代这些许可证。

- [python-audio-separator](https://github.com/nomadkaraoke/python-audio-separator)：MDX/BS 模型加载和分离引擎。
- [ClearerVoice-Studio](https://github.com/modelscope/ClearerVoice-Studio)：MossFormer2 语音增强。
- [FFmpeg](https://ffmpeg.org/) / [Gyan Windows builds](https://www.gyan.dev/ffmpeg/builds/)：音视频读取、转换和检查。
- [uv](https://github.com/astral-sh/uv) / [PyTorch](https://pytorch.org/)：本地依赖管理和推理运行环境。
