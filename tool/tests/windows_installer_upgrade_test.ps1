param([string]$InnoCompiler = 'ISCC.exe')

$ErrorActionPreference = 'Stop'
# This changes machine installation records: run only on disposable CI runners.
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Installer regression requires a disposable GitHub Actions runner' }
$workspace = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$taskRoot = Join-Path $workspace '.fvm/installer-upgrade-tests'
$taskBundle = Join-Path $taskRoot 'bundle'
New-Item -ItemType Directory -Path $taskBundle -Force | Out-Null
Copy-Item "$env:SystemRoot/System32/where.exe" (Join-Path $taskBundle 'pilipili.exe')
@{mode='release'; touchLoggingEnabled=$false; appVersion='0.0.0-installer-test'; appCommit='fixture'} |
    ConvertTo-Json | Set-Content (Join-Path $taskBundle 'release-build.json') -Encoding utf8
$taskAppId = ((Get-Content (Join-Path $workspace 'windows/packaging/exe/make_config.yaml') |
    Where-Object { $_ -match '^app_id:' }) -split ':', 2)[1].Trim()
$taskPrefix = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\'
$taskKeys = @("${taskAppId}_is1", "{${taskAppId}}_is1")
$taskRoots = foreach ($hive in @('LocalMachine', 'CurrentUser')) {
    foreach ($view in @('Registry64', 'Registry32')) {
        @{ hive=$hive; view=$view; base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view) }
    }
}
foreach ($root in $taskRoots) {
    foreach ($key in $taskKeys) {
        $existing = $root.base.OpenSubKey($taskPrefix + $key)
        if ($existing) { $existing.Dispose(); throw 'Runner already contains a Pilipili installation; refusing to change it' }
    }
}
function Clear-TestRecords {
    foreach ($root in $taskRoots) {
        foreach ($key in $taskKeys) { $root.base.DeleteSubKeyTree($taskPrefix + $key, $false) }
    }
}
function Run-Installer([string]$name, [string]$expected, [string]$override, [bool]$upgrade) {
    $log = Join-Path $taskRoot "$name.log"
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/LOG=`"$log`"")
    if ($override) { $arguments += "/DIR=`"$override`"" }
    $process = Start-Process -FilePath $taskInstaller -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
    if ($process.ExitCode -ne 0) { throw "Installer case $name failed: $($process.ExitCode)" }
    $text = Get-Content -LiteralPath $log -Raw
    if (-not $text.Contains("Pilipili selected install directory: $expected")) { throw "Wrong selected directory in $name`n$text" }
    if ($upgrade -and -not $text.Contains('Pilipili upgrade directory: ')) { throw "Upgrade not detected in $name" }
    if (-not $upgrade -and -not $text.Contains('Pilipili: no existing installation found')) { throw "Unexpected upgrade in $name" }
    if (-not (Test-Path -LiteralPath (Join-Path $expected 'release-build.json'))) { throw "Payload missing from $expected" }
    if (Test-Path -LiteralPath (Join-Path $expected 'piliplus.exe')) { throw "Legacy executable was not replaced in $name" }
    Write-Host "Installer regression passed: $name"
}
try {
    & (Join-Path $workspace 'tool/package_windows_release.ps1') -InnoCompiler $InnoCompiler -BundlePath $taskBundle -OutputDirectory (Join-Path $taskRoot 'package')
    $taskInstaller = (Get-ChildItem (Join-Path $taskRoot 'package') -Filter '*.exe').FullName
    foreach ($root in $taskRoots) {
        foreach ($key in $taskKeys) {
            foreach ($valueName in @('Inno Setup: App Path', 'InstallLocation')) {
                $name = "$($root.hive)-$($root.view)-$([array]::IndexOf($taskKeys, $key))-$($valueName.Replace(': ', '-').Replace(' ', '-'))"
                $previous = Join-Path $taskRoot "$name/PiliPlus custom path"
                New-Item -ItemType Directory -Path $previous -Force | Out-Null
                Copy-Item "$env:SystemRoot/System32/where.exe" (Join-Path $previous 'piliplus.exe')
                $record = $root.base.CreateSubKey($taskPrefix + $key)
                $record.SetValue($valueName, $previous)
                $record.Dispose()
                try { Run-Installer $name $previous '' $true } finally { Clear-TestRecords }
            }
        }
    }
    # Stale installation records must not hide the fresh-install directory page.
    $stale = $taskRoots[0].base.CreateSubKey($taskPrefix + $taskKeys[0])
    $stale.SetValue('InstallLocation', (Join-Path $taskRoot 'missing'))
    $stale.Dispose()
    try { Run-Installer 'stale-record' (Join-Path $taskRoot 'stale-fresh') (Join-Path $taskRoot 'stale-fresh') $false } finally { Clear-TestRecords }
    Run-Installer 'fresh' (Join-Path $taskRoot 'fresh') (Join-Path $taskRoot 'fresh') $false
} finally {
    Clear-TestRecords
    foreach ($root in $taskRoots) { $root.base.Dispose() }
}
