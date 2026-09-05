param([Parameter(Mandatory=$true)][string]$TempDir, [Parameter(Mandatory=$true)][string]$InputFile)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'app\gui.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'GUI parse failed'}
foreach($name in @('Read-CompleteLines','Handle-WorkerEvent','Handle-EngineLine')){
    $handler=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    Invoke-Expression $handler.Extent.Text
}
function Add-LogLine([string]$Text) { }
$progressBar=[PSCustomObject]@{Maximum=100;Value=0;Style='Continuous'}
$statusLabel=[PSCustomObject]@{Text=''}
$script:CompletedCount=0; $script:TotalCount=0; $script:BatchFinished=$false
$script:CurrentFileLabel=''; $script:ChunkLabel=''; $script:LastLoggedPercent=-10
$run=Join-Path $TempDir ([Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($run)
$events=Join-Path $run 'events.jsonl'; $log=Join-Path $run 'engine.log'; $jobFile=Join-Path $run 'job.json'
$job=@{model='bs_roformer_viperx_1297';files=@($InputFile);events=$events;engine_log=$log}
[IO.File]::WriteAllText($jobFile,($job|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=Join-Path $root '.runtime\python\python.exe'
$info.Arguments='-I -X utf8 "'+(Join-Path $root 'app\worker.py')+'" --job "'+$jobFile+'"'
$info.UseShellExecute=$false; $info.CreateNoWindow=$true
$info.EnvironmentVariables['AUDIO_SEPARATOR_TEMP']=$run
$info.EnvironmentVariables['TEMP']=$run; $info.EnvironmentVariables['TMP']=$run
$process=[Diagnostics.Process]::Start($info)
$eventOffset=0L; $logOffset=0L; $liveUpdates=0; $lastPercent=-1
while(-not $process.HasExited){
    Read-CompleteLines $events ([ref]$eventOffset) $true
    Read-CompleteLines $log ([ref]$logOffset) $false
    if(-not $script:BatchFinished -and $progressBar.Style -eq 'Continuous' -and $progressBar.Value -gt 0 -and $progressBar.Value -lt 100 -and $progressBar.Value -ne $lastPercent){
        $liveUpdates++; $lastPercent=$progressBar.Value
        Write-Output ('Observed live progress: '+$lastPercent+'%')
    }
    Start-Sleep -Milliseconds 300
}
Read-CompleteLines $events ([ref]$eventOffset) $true
Read-CompleteLines $log ([ref]$logOffset) $false $true
if($process.ExitCode -ne 0 -or -not $script:BatchFinished){throw "BS failed; inspect $run"}
if($liveUpdates -lt 2){throw "Insufficient progress updates: $liveUpdates"}
$report=@{success=$true;live_updates=$liveUpdates;exit_code=$process.ExitCode;final_status=$statusLabel.Text}
[IO.File]::WriteAllText((Join-Path $run 'result.json'),($report|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
$process.Dispose()
Write-Output ('BS real-inference progress verification passed: '+$liveUpdates+' updates')
