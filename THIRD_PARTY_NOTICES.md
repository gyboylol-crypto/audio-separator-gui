# 第三方组件说明

本文件记录当前本机项目实际使用的组件，不替代各项目的正式许可证文本。

## audio-separator 0.47.0

- 用途：模型下载、加载与音源分离引擎。
- 本机安装包元数据声明许可证为 MIT。
- 上游仓库：`https://github.com/karaokenerds/python-audio-separator`
- 随安装包保存的许可证：`.runtime/python/Lib/site-packages/audio_separator-0.47.0.dist-info/licenses/LICENSE`

本程序不是从零重写分离算法，而是在该成熟引擎之上实现 Windows 图形界面、批处理、视频抽轨、输出管理与安全边界。

## FFmpeg

- 当前 `ffmpeg.exe` 复制自本机 Ultimate Vocal Remover 安装目录。
- 当前 `ffprobe.exe` 来自 FFmpeg 官网下载页列出的 Gyan Windows release essentials 构建，并在安装时核对发布方 SHA-256。
- `ffmpeg -L` 显示该具体构建启用了 GPL，并按 GPLv3 或更高版本分发。
- 仅供本机使用没有额外打包动作；若发布安装包，不应在未履行 GPL 义务的情况下直接捆绑该二进制文件。

## 模型权重

- MDX23C 权重由 `audio-separator` 的公开 UVR 模型清单解析并下载。
- “可公开下载”不等于自动授予任意再分发权。本项目目前将权重保存在本机 `.models`，并通过 `.gitignore` 排除。
- 若要向他人发布含权重的完整压缩包或安装器，应先核对模型作者/仓库当时的明确许可；更稳妥的发布方式是让用户在首次使用时自行下载。

## ClearVoice / MossFormer2

v2 使用 ClearVoice 0.1.2，代码来源为 https://github.com/modelscope/ClearerVoice-Studio ，项目声明 Apache-2.0。

MossFormer2_SE_48K 权重来自 https://huggingface.co/alibabasglab/MossFormer2_SE_48K ，模型页声明 Apache-2.0；部署固定 revision `eff8c97925c8bec812af707814b3e5d777fd4503`。

Moss 使用独立 Python 环境，避免与 audio-separator 的 numpy、rotary embedding 版本要求冲突。已完成本机真实推理验收，不再额外生成背景残差。

## v2 发布边界

公开版本仅包含自有源码、说明及安装入口，不包含 FFmpeg 二进制、模型权重、Python 或依赖运行库。安装入口从上游下载这些组件，使用时需遵守各自许可证。

项目所有者已选择 MIT 许可证用于本项目自有 GUI、适配和批处理代码，见 `LICENSE`。该许可证不替代第三方组件或模型的许可证。完整包在技术上可携带这些文件，但公开下载不等于所有权重都允许任意再分发，当前不发布离线完整包。
