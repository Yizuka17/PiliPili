param([string]$OutputDirectory = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$logDir = Join-Path ([IO.Path]::GetTempPath()) 'Pilipili-touch-logs'
$files = @(Get-ChildItem -LiteralPath $logDir -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)
if ($files.Count -eq 0) { throw "No touch logs found in $logDir. Run the debug client first." }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$destination = Join-Path $OutputDirectory ('Pilipili-touch-logs-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
Compress-Archive -LiteralPath $files.FullName -DestinationPath $destination
Write-Host "Touch logs: $destination"
