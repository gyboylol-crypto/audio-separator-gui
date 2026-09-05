param([switch]$NonInteractive)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeRoot = Join-Path $ProjectRoot '.runtime'
$PythonRoot = Join-Path $RuntimeRoot 'python'
$VenvPython = Join-Path $PythonRoot 'python.exe'
$UvRoot = Join-Path $RuntimeRoot 'uv'
$UvExe = Join-Path $UvRoot 'uv.exe'
$FfmpegRoot = Join-Path $RuntimeRoot 'ffmpeg'
$FfmpegExe = Join-Path $FfmpegRoot 'ffmpeg.exe'
$FfprobeExe = Join-Path $FfmpegRoot 'ffprobe.exe'
$FfmpegZipUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
$FfmpegShaUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip.sha256'
$env:UV_CACHE_DIR = Join-Path $RuntimeRoot 'uv-cache'
$env:UV_PYTHON_INSTALL_DIR = Join-Path $RuntimeRoot 'managed-python'
$env:UV_LINK_MODE = 'copy'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

Write-Host '正在准备本地音频分离器运行环境……'
[IO.Directory]::CreateDirectory($RuntimeRoot) | Out-Null
[IO.Directory]::CreateDirectory($UvRoot) | Out-Null
[IO.Directory]::CreateDirectory($FfmpegRoot) | Out-Null

if (-not (Test-Path -LiteralPath $FfmpegExe) -or -not (Test-Path -LiteralPath $FfprobeExe)) {
    Write-Host '正在下载 FFmpeg/FFprobe Windows 工具……'
    $downloadRoot = Join-Path $RuntimeRoot 'downloads'
    $extractRoot = Join-Path $downloadRoot ('ffmpeg-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($downloadRoot) | Out-Null
    $zipPath = Join-Path $downloadRoot 'ffmpeg-release-essentials.zip'
    $shaPath = Join-Path $downloadRoot 'ffmpeg-release-essentials.zip.sha256'
    Invoke-WebRequest -UseBasicParsing -Uri $FfmpegZipUrl -OutFile $zipPath
    Invoke-WebRequest -UseBasicParsing -Uri $FfmpegShaUrl -OutFile $shaPath
    $expectedSha = ((Get-Content -LiteralPath $shaPath -Raw).Trim() -split '\s+')[0].ToUpperInvariant()
    $actualSha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($expectedSha -ne $actualSha) { throw 'FFmpeg 压缩包 SHA-256 校验失败。' }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot
    $downloadedFfmpeg = Get-ChildItem -LiteralPath $extractRoot -Recurse -File -Filter 'ffmpeg.exe' | Select-Object -First 1
    $downloadedFfprobe = Get-ChildItem -LiteralPath $extractRoot -Recurse -File -Filter 'ffprobe.exe' | Select-Object -First 1
    if (-not $downloadedFfmpeg -or -not $downloadedFfprobe) { throw '下载包中缺少 FFmpeg 或 FFprobe。' }
    if (-not (Test-Path -LiteralPath $FfmpegExe)) { Copy-Item -LiteralPath $downloadedFfmpeg.FullName -Destination $FfmpegExe }
    if (-not (Test-Path -LiteralPath $FfprobeExe)) { Copy-Item -LiteralPath $downloadedFfprobe.FullName -Destination $FfprobeExe }
}

if (-not (Test-Path -LiteralPath $UvExe)) {
    $downloadRoot = Join-Path $RuntimeRoot 'downloads'
    [IO.Directory]::CreateDirectory($downloadRoot) | Out-Null
    $zipPath = Join-Path $downloadRoot 'uv-x86_64-pc-windows-msvc.zip'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/astral-sh/uv/releases/download/0.12.9/uv-x86_64-pc-windows-msvc.zip' -OutFile $zipPath
    $uvShaPath = Join-Path $downloadRoot 'uv-x86_64-pc-windows-msvc.zip.sha256'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/astral-sh/uv/releases/download/0.12.9/uv-x86_64-pc-windows-msvc.zip.sha256' -OutFile $uvShaPath
    $uvExpectedSha = ((Get-Content -LiteralPath $uvShaPath -Raw).Trim() -split '\s+')[0]
    if ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ne $uvExpectedSha) { throw 'uv 压缩包 SHA-256 校验失败。' }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $UvRoot
}

if (-not (Test-Path -LiteralPath $VenvPython)) {
    & $UvExe python install 3.12.14 --no-bin
    if ($LASTEXITCODE -ne 0) { throw 'Python 下载失败。' }
    $base = Get-ChildItem -LiteralPath $env:UV_PYTHON_INSTALL_DIR -Directory | Where-Object { $_.Name -eq 'cpython-3.12.14-windows-x86_64-none' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | Select-Object -First 1
    if (-not $base) { throw '未找到独立 Python 下载目录。' }
    & robocopy.exe $base.FullName $PythonRoot /E /XJ /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw '复制独立 Python 运行环境失败。' }
}

& $UvExe pip install --python $VenvPython --break-system-packages -r (Join-Path $ProjectRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw '分离引擎依赖安装失败。' }

# PyPI may select a CPU-only Torch build on Windows. Probe the existing project
# environment first so rerunning setup does not download the large CUDA wheel.
& $VenvPython -c "import sys, torch; sys.exit(0 if '+cu130' in torch.__version__ else 1)"
if ($LASTEXITCODE -eq 0) {
    Write-Host '已检测到可用的 CUDA Torch，跳过重复下载。'
} else {
    & $UvExe pip install --python $VenvPython --break-system-packages --index-url 'https://download.pytorch.org/whl/cu130' --reinstall-package torch --reinstall-package torchvision 'torch==2.14.0' 'torchvision==0.29.0'
    if ($LASTEXITCODE -ne 0) { throw 'PyTorch CUDA 运行库安装失败。' }
}

Write-Host ''
& (Join-Path $ProjectRoot 'setup-mossformer.ps1') -NonInteractive
& $VenvPython -X utf8 (Join-Path $ProjectRoot 'app\deploy_models.py') --only separation
if ($LASTEXITCODE -ne 0) { throw '模型下载失败，请重新运行部署模型入口。' }
Write-Host '基础运行环境安装完成。现在可以双击“启动音频分离器.cmd”。' -ForegroundColor Green
if (-not $NonInteractive) { Read-Host '按回车键关闭' }
