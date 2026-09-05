param([switch]$NonInteractive)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$UvExe = Join-Path $ProjectRoot '.runtime\uv\uv.exe'
$PythonRoot = Join-Path $ProjectRoot '.runtime\moss-python'
$PythonExe = Join-Path $PythonRoot 'python.exe'
$Base = Join-Path $ProjectRoot '.runtime\python'
$env:UV_CACHE_DIR = Join-Path $ProjectRoot '.runtime\uv-cache'
if (-not (Test-Path -LiteralPath (Join-Path $Base 'python.exe'))) { throw '请先运行 setup.cmd 安装基础环境。' }
if (-not (Test-Path -LiteralPath $UvExe)) { throw '缺少 uv.exe，请重新运行 setup.cmd。' }
$env:UV_LINK_MODE = 'copy'
if (-not (Test-Path -LiteralPath $PythonExe)) {
    & robocopy.exe $Base $PythonRoot /E /XJ /XD (Join-Path $Base 'Lib\site-packages') (Join-Path $Base 'Scripts') __pycache__ /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw '复制独立 Moss Python 失败。' }
}
& $UvExe pip install --python $PythonExe --break-system-packages --index-url 'https://download.pytorch.org/whl/cu128' 'torch==2.8.0' 'torchaudio==2.8.0' 'torchvision==0.23.0'
if ($LASTEXITCODE -ne 0) { throw 'Moss GPU 运行库安装失败。' }
& $UvExe pip install --python $PythonExe --break-system-packages 'clearvoice==0.1.2' 'numpy==1.26.4'
if ($LASTEXITCODE -ne 0) { throw 'MossFormer2/ClearVoice 安装失败。' }
& $PythonExe -X utf8 (Join-Path $ProjectRoot 'app\deploy_models.py') --only moss
if ($LASTEXITCODE -ne 0) { throw 'Moss 模型下载失败。' }
Write-Host 'MossFormer2 SE 48K 独立运行环境和模型已安装。' -ForegroundColor Green
if (-not $NonInteractive) { Read-Host '按回车键关闭' }
