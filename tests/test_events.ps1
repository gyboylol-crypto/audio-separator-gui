param([Parameter(Mandatory=$true)][string]$TempDir)
$ErrorActionPreference = 'Stop'
$gui = Join-Path (Split-Path $PSScriptRoot) 'app\gui.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($gui, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'GUI parse failed' }
$function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Read-CompleteLines' }, $true)
# Evaluate only the pure log-reader function, not the form or UI controls.
Invoke-Expression $function.Extent.Text
$script:Received = New-Object Collections.Generic.List[string]
function Handle-WorkerEvent([string]$Line) { $script:Received.Add($Line) }
function Add-LogLine([string]$Line) { $script:Received.Add($Line) }
function Handle-EngineLine([string]$Line) { if ($Line) { $script:Received.Add($Line) } }
$path = Join-Path $TempDir ('events-' + [Guid]::NewGuid().ToString('N') + '.jsonl')
$message = [string][char]0x4e2d + [char]0x6587
$line = (@{type='engine_log'; message=$message} | ConvertTo-Json -Compress) + "`n"
$bytes = [Text.Encoding]::UTF8.GetBytes($line)
$offset = 0L
# An incomplete UTF-8 multibyte character must remain unread until newline.
$cut = [Array]::IndexOf($bytes, [byte]0xE4) + 1
[IO.File]::WriteAllBytes($path, $bytes[0..($cut-1)])
Read-CompleteLines $path ([ref]$offset) $true
if ($offset -ne 0 -or $script:Received.Count -ne 0) { throw 'Partial line consumed' }
[IO.File]::WriteAllBytes($path, $bytes)
Read-CompleteLines $path ([ref]$offset) $true
if ($offset -ne $bytes.Length -or $script:Received.Count -ne 1) { throw 'Complete line not consumed once' }
$parsed = $script:Received[0] | ConvertFrom-Json
if ($parsed.message -ne $message) { throw 'UTF-8 text corrupted' }
Read-CompleteLines $path ([ref]$offset) $true
if ($script:Received.Count -ne 1) { throw 'Duplicate event' }
Write-Output 'Windows PowerShell UTF-8 partial-line event tests: passed'

$script:Received.Clear()
$progressText = "`r 10%|abc| 10/100 [00:01<00:09, 10it/s]`r 20%|abc| 20/100 [00:02<00:08, 10it/s]`r"
$progressPath = Join-Path $TempDir ('progress-' + [Guid]::NewGuid().ToString('N') + '.log')
[IO.File]::WriteAllText($progressPath, $progressText, (New-Object Text.UTF8Encoding($false)))
$progressOffset = 0L
Read-CompleteLines $progressPath ([ref]$progressOffset) $false
if ($script:Received.Count -ne 2) { throw 'Carriage-return progress not delivered before newline' }
[IO.File]::AppendAllText($progressPath, 'last diagnostic without newline', (New-Object Text.UTF8Encoding($false)))
Read-CompleteLines $progressPath ([ref]$progressOffset) $false $true
if ($script:Received.Count -ne 3) { throw 'Final diagnostic not flushed' }

# Test real GUI event handlers using simple state objects, without creating UI.
foreach ($name in @('Handle-WorkerEvent','Handle-EngineLine')) {
    $handler = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    Invoke-Expression $handler.Extent.Text
}
$progressBar = [PSCustomObject]@{Maximum=100;Value=0;Style='Continuous'}
$statusLabel = [PSCustomObject]@{Text=''}
$script:CompletedCount=0
Handle-WorkerEvent '{"type":"batch_started","total":1,"model":"BS"}'
Handle-WorkerEvent '{"type":"file_started","index":1,"total":1,"path":"test.wav"}'
if ($progressBar.Style -ne 'Marquee') { throw 'Loading indicator missing' }
Handle-EngineLine 'INFO Processing chunk 1/2: test.wav'
Handle-EngineLine ' 60%|abc| 178/297 [02:53<02:04, 1.05s/it]'
if ($progressBar.Value -ne 60 -or $statusLabel.Text -notlike '*60%*' -or $statusLabel.Text -notlike '*1/2*') { throw 'Live chunk percentage missing' }
Handle-EngineLine 'INFO Processing chunk 2/2: next.wav'
if ($progressBar.Value -ne 0 -or $statusLabel.Text -notlike '*2/2*') { throw 'Chunk reset missing' }
Handle-EngineLine 'INFO Merging 2 chunks for stem: Vocals'
if ($progressBar.Style -ne 'Marquee') { throw 'Merge indicator missing' }
Handle-WorkerEvent '{"type":"batch_completed","succeeded":1,"failed":0}'
$finalText=$statusLabel.Text
Handle-EngineLine ' 99%|abc| 99/100 [00:09<00:01, 10it/s]'
if ($statusLabel.Text -ne $finalText -or $progressBar.Value -ne 100) { throw 'Late log overwrote completion' }
Write-Output 'CR progress, chunk transitions, merge and completion tests: passed'
