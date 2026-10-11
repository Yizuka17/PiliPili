param(
    [Parameter(Mandatory)][string]$Bundle,
    [Parameter(Mandatory)][string]$VisualStudioRoot
)

$ErrorActionPreference = 'Stop'
$taskBundlePath = (Resolve-Path -LiteralPath $Bundle).Path
if (-not (Test-Path -LiteralPath (Join-Path $taskBundlePath 'pilipili.exe'))) {
    throw 'Windows release executable missing'
}
$taskRedistRoot = Join-Path $VisualStudioRoot 'VC/Redist/MSVC'
$taskRedist = Get-ChildItem -LiteralPath $taskRedistRoot -Directory |
    Where-Object Name -Match '^\d+\.\d+\.\d+$' |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $taskRedist) { throw 'MSVC redistributable directory missing' }
$taskCrt = Get-ChildItem -Path (Join-Path $taskRedist.FullName 'x64/Microsoft.VC*.CRT') -Directory |
    Select-Object -First 1
if (-not $taskCrt) { throw 'MSVC x64 release runtime missing' }
$taskRuntimeFiles = @(Get-ChildItem -LiteralPath $taskCrt.FullName -Filter '*.dll' -File)
if (-not $taskRuntimeFiles) { throw 'No MSVC runtime DLLs found' }
foreach ($taskRuntime in $taskRuntimeFiles) {
    Copy-Item -LiteralPath $taskRuntime.FullName -Destination $taskBundlePath
}

# ANGLE bundles an unused debug zlib. Never distribute a dependency requiring
# Microsoft's non-redistributable debug runtime with the production release.
$taskUnusedZlib = Join-Path $taskBundlePath 'zlib.dll'
if (Test-Path -LiteralPath $taskUnusedZlib) {
    foreach ($taskBinary in (Get-ChildItem -LiteralPath $taskBundlePath -File |
        Where-Object { $_.Extension -in '.exe', '.dll' -and $_.Name -ne 'zlib.dll' })) {
        $taskBytes = [IO.File]::ReadAllBytes($taskBinary.FullName)
        if ([Text.Encoding]::ASCII.GetString($taskBytes).ToLowerInvariant().Contains('zlib.dll') -or
            [Text.Encoding]::Unicode.GetString($taskBytes).ToLowerInvariant().Contains('zlib.dll')) {
            throw "Cannot omit zlib.dll: referenced by $($taskBinary.Name)"
        }
    }
    Remove-Item -LiteralPath $taskUnusedZlib
}
Write-Host "Bundled MSVC $($taskRedist.Name) x64 runtime: $($taskRuntimeFiles.Count) DLLs"
