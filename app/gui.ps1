Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:PythonExe = Join-Path $script:ProjectRoot '.runtime\python\python.exe'
$script:WorkerScript = Join-Path $PSScriptRoot 'worker.py'
$script:ModelsPath = Join-Path $PSScriptRoot 'models.json'
$script:ModelDir = Join-Path $script:ProjectRoot '.models'
$script:WorkerProcess = $null
$script:WorkerOutFile = $null
$script:WorkerErrFile = $null
$script:ReadOffset = 0
$script:ErrReadOffset = 0
$script:CompletedCount = 0
$script:TotalCount = 0
$script:CurrentFileLabel = ''
$script:ChunkLabel = ''
$script:LastLoggedPercent = -10
$script:BatchFinished = $false

function Add-LogLine([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logBox.AppendText("[$timestamp] $Text`r`n")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
}

function Add-InputPath([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $allowed = @('.mp3','.mp4','.wav','.flac','.m4a','.aac','.ogg','.wma','.opus','.mkv','.mov','.webm','.avi')
    if ($allowed -notcontains [IO.Path]::GetExtension($Path).ToLowerInvariant()) { return }
    for ($i = 0; $i -lt $fileList.Items.Count; $i++) {
        if ([string]::Equals($fileList.Items[$i].ToString(), $Path, [StringComparison]::OrdinalIgnoreCase)) { return }
    }
    [void]$fileList.Items.Add($Path)
    if ($emptyHint) { $emptyHint.Visible = $false }
}

function Add-FolderFiles([string]$Folder) {
    Get-ChildItem -LiteralPath $Folder -File -ErrorAction SilentlyContinue | ForEach-Object { Add-InputPath $_.FullName }
}

function Set-RunningState([bool]$Running) {
    $startButton.Enabled = -not $Running
    $cancelButton.Enabled = $Running
    $addFilesButton.Enabled = -not $Running
    $addFolderButton.Enabled = -not $Running
    $removeButton.Enabled = -not $Running
    $clearButton.Enabled = -not $Running
    $modelCombo.Enabled = -not $Running
}

function Handle-EngineLine([string]$Line) {
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    if ($Line -match '^\s*(\d{1,3})%\|.*\|\s*(\d+)/(\d+)\s*\[([^\]]+)\]') {
        $percent = [Math]::Min(100, [int]$Matches[1])
        $steps = "$($Matches[2])/$($Matches[3])"
        $timing = $Matches[4]
        if (-not $script:BatchFinished) {
            $progressBar.Style = 'Continuous'
            $progressBar.Value = $percent
            $statusLabel.Text = "$script:CurrentFileLabel · $script:ChunkLabel 当前计算 $percent%（$steps）[$timing]"
            if ($percent -lt $script:LastLoggedPercent -or $percent -ge ($script:LastLoggedPercent + 10) -or $percent -eq 100) {
                Add-LogLine "$script:ChunkLabel 当前计算 $percent%（$steps）[$timing]"
                $script:LastLoggedPercent = $percent
            }
        }
        return
    }
    if ($Line -match 'Processing chunk (\d+)/(\d+):') {
        $script:ChunkLabel = "分块 $($Matches[1])/$($Matches[2])"
        $script:LastLoggedPercent = -10
        if (-not $script:BatchFinished) {
            $progressBar.Value = 0
            $statusLabel.Text = "$script:CurrentFileLabel · $script:ChunkLabel 准备计算……"
        }
    }
    if ($Line -match 'Saving .* stem|Merging \d+ chunks|Exporting merged audio') {
        if (-not $script:BatchFinished) {
            $progressBar.Style = 'Marquee'
            $statusLabel.Text = "$script:CurrentFileLabel · 正在写入/合并音轨，请稍候……"
        }
    }
    Add-LogLine $Line
}

function Handle-WorkerEvent([string]$Line) {
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    try { $event = $Line | ConvertFrom-Json -ErrorAction Stop }
    catch { Add-LogLine $Line; return }
    switch ($event.type) {
        'batch_started' {
            $script:TotalCount = [int]$event.total
            $progressBar.Maximum = 100
            $script:BatchFinished = $false
            Add-LogLine "开始批处理：$($event.model)，共 $($event.total) 个文件。"
            Add-LogLine '进度条显示当前计算分块；长音频切换分块时会重新从 0% 开始。'
        }
        'file_started' {
            $script:CurrentFileLabel = "文件 $($event.index)/$($event.total)：$([IO.Path]::GetFileName($event.path))"
            $script:ChunkLabel = ''
            $script:LastLoggedPercent = -10
            $progressBar.Value = 0
            $progressBar.Style = 'Marquee'
            $statusLabel.Text = "$script:CurrentFileLabel · 正在准备模型和音频……"
            Add-LogLine "正在处理：$($event.path)"
        }
        'engine_log' { Add-LogLine $event.message }
        'file_completed' {
            $script:CompletedCount++
            $progressBar.Style = 'Continuous'
            $progressBar.Value = 100
            foreach ($output in $event.outputs) { Add-LogLine "完成：$output" }
        }
        'file_failed' {
            $script:CompletedCount++
            $progressBar.Style = 'Continuous'
            $progressBar.Value = 0
            Add-LogLine "失败：$($event.path)；$($event.error)"
        }
        'batch_completed' {
            $script:BatchFinished = $true
            $progressBar.Style = 'Continuous'
            $progressBar.Value = 100
            $statusLabel.Text = "完成：成功 $($event.succeeded)，失败 $($event.failed)"
            Add-LogLine $statusLabel.Text
        }
        'fatal' {
            $script:BatchFinished = $true
            $progressBar.Style = 'Continuous'
            $statusLabel.Text = '任务失败'
            Add-LogLine "严重错误：$($event.error)"
        }
        default { Add-LogLine $Line }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = '本地音频工具 v2 — 分离 / 降噪'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object Drawing.Size(900, 650)
$form.MinimumSize = New-Object Drawing.Size(760, 540)
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)
$form.BackColor = [Drawing.Color]::FromArgb(245, 247, 250)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = '本地音频工具 v2'
$titleLabel.Font = New-Object Drawing.Font('Microsoft YaHei UI', 18, [Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object Drawing.Point(24, 18)
$titleLabel.AutoSize = $true
$form.Controls.Add($titleLabel)

$hintLabel = New-Object System.Windows.Forms.Label
$hintLabel.Text = '拖入音频或视频，结果自动输出到原文件目录；原文件不会被修改。'
$hintLabel.Location = New-Object Drawing.Point(27, 58)
$hintLabel.AutoSize = $true
$hintLabel.ForeColor = [Drawing.Color]::DimGray
$form.Controls.Add($hintLabel)

$modelLabel = New-Object System.Windows.Forms.Label
$modelLabel.Text = '处理模型'
$modelLabel.Location = New-Object Drawing.Point(26, 94)
$modelLabel.AutoSize = $true
$form.Controls.Add($modelLabel)

$modelCombo = New-Object System.Windows.Forms.ComboBox
$modelCombo.DropDownStyle = 'DropDownList'
$modelCombo.Location = New-Object Drawing.Point(105, 90)
$modelCombo.Size = New-Object Drawing.Size(620, 28)
$modelCombo.DropDownWidth = 680
$models = Get-Content -LiteralPath $script:ModelsPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($model in $models) {
    if ($model.enabled) {
        $item = [PSCustomObject]@{ Name = $model.name; Id = $model.id; Description = $model.description; Engine = $model.engine }
        [void]$modelCombo.Items.Add($item)
    }
}
$modelCombo.DisplayMember = 'Name'
if ($modelCombo.Items.Count -gt 0) { $modelCombo.SelectedIndex = 0 }
$form.Controls.Add($modelCombo)

$modelDescription = New-Object System.Windows.Forms.Label
$modelDescription.Location = New-Object Drawing.Point(105, 122)
$modelDescription.Size = New-Object Drawing.Size(700, 38)
$modelDescription.ForeColor = [Drawing.Color]::DimGray
$form.Controls.Add($modelDescription)
$modelCombo.Add_SelectedIndexChanged({
    if ($modelCombo.SelectedItem) {
        $modelDescription.Text = $modelCombo.SelectedItem.Description
        if ($startButton) { $startButton.Text = if ($modelCombo.SelectedItem.Engine -eq 'clearvoice') { '开始降噪' } else { '开始分离' } }
    }
})
if ($modelCombo.SelectedItem) { $modelDescription.Text = $modelCombo.SelectedItem.Description }

$fileList = New-Object System.Windows.Forms.ListBox
$fileList.Location = New-Object Drawing.Point(28, 164)
$fileList.Size = New-Object Drawing.Size(820, 190)
$fileList.Anchor = 'Top,Left,Right'
$fileList.SelectionMode = 'MultiExtended'
$fileList.AllowDrop = $true
$fileList.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
$fileList.Add_DragDrop({
    if ($script:WorkerProcess) { return }
    foreach ($path in $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) {
        if (Test-Path -LiteralPath $path -PathType Container) { Add-FolderFiles $path } else { Add-InputPath $path }
    }
})
$form.Controls.Add($fileList)

# A real child control keeps the empty-state hint centered when the list resizes.
# It accepts the same drops as the list, so the hint never blocks file dragging.
$emptyHint = New-Object System.Windows.Forms.Label
$emptyHint.Text = '可拖动文件到窗口'
$emptyHint.ForeColor = [Drawing.Color]::FromArgb(160, 166, 174)
$emptyHint.BackColor = $fileList.BackColor
$emptyHint.Font = New-Object Drawing.Font('Microsoft YaHei UI', 12)
$emptyHint.TextAlign = 'MiddleCenter'
$emptyHint.Dock = 'Fill'
$emptyHint.AllowDrop = $true
$emptyHint.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
$emptyHint.Add_DragDrop({
    if ($script:WorkerProcess) { return }
    foreach ($path in $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) {
        if (Test-Path -LiteralPath $path -PathType Container) { Add-FolderFiles $path } else { Add-InputPath $path }
    }
})
$fileList.Controls.Add($emptyHint)

$addFilesButton = New-Object System.Windows.Forms.Button
$addFilesButton.Text = '添加文件'
$addFilesButton.Location = New-Object Drawing.Point(28, 366)
$addFilesButton.Size = New-Object Drawing.Size(105, 34)
$addFilesButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.Filter = '音视频文件|*.mp3;*.mp4;*.wav;*.flac;*.m4a;*.aac;*.ogg;*.wma;*.opus;*.mkv;*.mov;*.webm;*.avi|所有文件|*.*'
    if ($dialog.ShowDialog() -eq 'OK') { foreach ($path in $dialog.FileNames) { Add-InputPath $path } }
})
$form.Controls.Add($addFilesButton)

$addFolderButton = New-Object System.Windows.Forms.Button
$addFolderButton.Text = '添加文件夹'
$addFolderButton.Location = New-Object Drawing.Point(141, 366)
$addFolderButton.Size = New-Object Drawing.Size(105, 34)
$addFolderButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq 'OK') { Add-FolderFiles $dialog.SelectedPath }
})
$form.Controls.Add($addFolderButton)

$removeButton = New-Object System.Windows.Forms.Button
$removeButton.Text = '移除选中'
$removeButton.Location = New-Object Drawing.Point(254, 366)
$removeButton.Size = New-Object Drawing.Size(105, 34)
$removeButton.Add_Click({
    $selected = @($fileList.SelectedItems)
    foreach ($item in $selected) { $fileList.Items.Remove($item) }
    $emptyHint.Visible = ($fileList.Items.Count -eq 0)
})
$form.Controls.Add($removeButton)

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = '清空'
$clearButton.Location = New-Object Drawing.Point(367, 366)
$clearButton.Size = New-Object Drawing.Size(80, 34)
$clearButton.Add_Click({ $fileList.Items.Clear(); $emptyHint.Visible = $true })
$form.Controls.Add($clearButton)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = '开始分离'
$startButton.Location = New-Object Drawing.Point(630, 366)
$startButton.Size = New-Object Drawing.Size(105, 34)
$startButton.Anchor = 'Top,Right'
$startButton.BackColor = [Drawing.Color]::FromArgb(0, 120, 212)
$startButton.ForeColor = [Drawing.Color]::White
$startButton.FlatStyle = 'Flat'
$form.Controls.Add($startButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = '取消任务'
$cancelButton.Location = New-Object Drawing.Point(743, 366)
$cancelButton.Size = New-Object Drawing.Size(105, 34)
$cancelButton.Anchor = 'Top,Right'
$cancelButton.Enabled = $false
$form.Controls.Add($cancelButton)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object Drawing.Point(28, 414)
$progressBar.Size = New-Object Drawing.Size(820, 18)
$progressBar.Anchor = 'Top,Left,Right'
$form.Controls.Add($progressBar)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = '就绪'
$statusLabel.Location = New-Object Drawing.Point(28, 438)
$statusLabel.Size = New-Object Drawing.Size(820, 24)
$statusLabel.Anchor = 'Top,Left,Right'
$form.Controls.Add($statusLabel)

$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Location = New-Object Drawing.Point(28, 466)
$logBox.Size = New-Object Drawing.Size(820, 118)
$logBox.Anchor = 'Top,Bottom,Left,Right'
$logBox.ReadOnly = $true
$logBox.BackColor = [Drawing.Color]::White
$form.Controls.Add($logBox)

function Read-CompleteLines([string]$Path, [ref]$Offset, [bool]$Events, [bool]$Flush = $false) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        [void]$stream.Seek($Offset.Value, 'Begin')
        $bytes = New-Object byte[] ([int]($stream.Length - $Offset.Value))
        $count = $stream.Read($bytes, 0, $bytes.Length)
        $start = 0
        for ($i = 0; $i -lt $count; $i++) {
            if ($bytes[$i] -eq 10 -or (-not $Events -and $bytes[$i] -eq 13)) {
                $line = [Text.Encoding]::UTF8.GetString($bytes, $start, $i - $start).TrimEnd("`r")
                if ($Events) { Handle-WorkerEvent $line } else { Handle-EngineLine $line }
                $start = $i + 1
            }
        }
        if ($Flush -and -not $Events -and $start -lt $count) {
            Handle-EngineLine ([Text.Encoding]::UTF8.GetString($bytes, $start, $count - $start))
            $start = $count
        }
        $Offset.Value += $start
    } finally { $stream.Dispose() }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    Read-CompleteLines $script:WorkerOutFile ([ref]$script:ReadOffset) $true
    Read-CompleteLines $script:WorkerErrFile ([ref]$script:ErrReadOffset) $false
    if ($script:WorkerProcess -and $script:WorkerProcess.HasExited) {
        Read-CompleteLines $script:WorkerOutFile ([ref]$script:ReadOffset) $true
        Read-CompleteLines $script:WorkerErrFile ([ref]$script:ErrReadOffset) $false $true
        $timer.Stop()
        Set-RunningState $false
        $progressBar.Style = 'Continuous'
        if (-not $script:BatchFinished -and $statusLabel.Text -ne '任务已取消') {
            $statusLabel.Text = if ($script:WorkerProcess.ExitCode -eq 0) { '处理完成' } else { "处理结束，退出码 $($script:WorkerProcess.ExitCode)" }
        }
        if ($script:WorkerProcess.ExitCode -ne 0) {
            Add-LogLine '若日志没有具体错误，请运行“环境检查.cmd”；DLL 缺失通常需要微软 VC++ x64 运行库，GPU 驱动问题请更新 NVIDIA 驱动。'
        }
        $script:WorkerProcess.Dispose()
        $script:WorkerProcess = $null
    }
})

$startButton.Add_Click({
    if (-not (Test-Path -LiteralPath $script:PythonExe -PathType Leaf)) {
        [Windows.Forms.MessageBox]::Show('运行环境尚未安装，请先双击 setup.cmd。', '缺少运行环境', 'OK', 'Warning') | Out-Null
        return
    }
    if ($fileList.Items.Count -eq 0) {
        [Windows.Forms.MessageBox]::Show('请先添加至少一个音频或视频文件。', '没有输入文件', 'OK', 'Information') | Out-Null
        return
    }
    if (-not $modelCombo.SelectedItem) { return }
    $script:CompletedCount = 0
    $script:BatchFinished = $false
    $script:ReadOffset = 0
    $script:ErrReadOffset = 0
    $progressBar.Value = 0
    $logBox.Clear()
    $runId = [Guid]::NewGuid().ToString('N')
    $logRoot = if ($env:AUDIO_SEPARATOR_LOG_ROOT) { $env:AUDIO_SEPARATOR_LOG_ROOT } else { Join-Path $script:ProjectRoot '.cache\logs' }
    $runDir = Join-Path $logRoot $runId
    [IO.Directory]::CreateDirectory($runDir) | Out-Null
    $script:WorkerOutFile = Join-Path $runDir "$runId.out.log"
    $script:WorkerErrFile = Join-Path $runDir "$runId.err.log"
    $jobFile = Join-Path $runDir 'job.json'
    $job = @{ model = $modelCombo.SelectedItem.Id; model_dir = $script:ModelDir; files = @($fileList.Items | ForEach-Object { $_.ToString() }); events = $script:WorkerOutFile; engine_log = $script:WorkerErrFile }
    [IO.File]::WriteAllText($jobFile, ($job | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:PythonExe
    $info.Arguments = '-I -X utf8 "' + $script:WorkerScript + '" --job "' + $jobFile + '"'
    $info.WorkingDirectory = $script:ProjectRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    try { $script:WorkerProcess = [Diagnostics.Process]::Start($info) }
    catch { Add-LogLine "启动失败：$($_.Exception.Message)。请运行环境检查；可能缺少 Windows x64 VC++ 运行库。"; return }
    Set-RunningState $true
    $progressBar.Style = 'Marquee'
    $statusLabel.Text = '正在启动处理引擎……'
    $timer.Start()
})

$cancelButton.Add_Click({
    if ($script:WorkerProcess -and -not $script:WorkerProcess.HasExited) {
        & "$env:SystemRoot\System32\taskkill.exe" /PID $script:WorkerProcess.Id /T /F | Out-Null
        $script:BatchFinished = $true
        $progressBar.Style = 'Continuous'
        Add-LogLine '用户已取消任务。'
        $statusLabel.Text = '任务已取消'
    }
})

$form.Add_FormClosing({
    if ($script:WorkerProcess -and -not $script:WorkerProcess.HasExited) {
        $choice = [Windows.Forms.MessageBox]::Show('任务仍在运行，确定退出并取消任务吗？', '确认退出', 'YesNo', 'Question')
        if ($choice -ne 'Yes') { $_.Cancel = $true; return }
        & "$env:SystemRoot\System32\taskkill.exe" /PID $script:WorkerProcess.Id /T /F | Out-Null
    }
})

[void]$form.ShowDialog()
