param([string]$InnoCompiler = 'ISCC.exe')

$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
$bundle = Join-Path $workspace 'build/windows/x64/runner/Release'
$manifest = Get-Content (Join-Path $bundle 'release-build.json') -Raw | ConvertFrom-Json
if ($manifest.mode -ne 'release' -or $manifest.touchLoggingEnabled) {
    throw 'Build a production release before packaging'
}
if (-not (Test-Path -LiteralPath (Join-Path $bundle 'pilipili.exe'))) {
    throw 'Pilipili executable missing'
}
$configPath = Join-Path $workspace 'windows/packaging/exe/make_config.yaml'
$config = @{}
foreach ($line in Get-Content -LiteralPath $configPath) {
    if ($line -match '^([a-z_]+):\s*(.+)$') { $config[$matches[1]] = $matches[2] }
}
$baseName = "Pilipili_windows_$($manifest.appVersion)_x64_setup"
$values = @{
    APP_ID = $config.app_id
    APP_VERSION = $manifest.appVersion
    DISPLAY_NAME = $config.display_name
    PUBLISHER_NAME = $config.publisher
    PUBLISHER_URL = $config.publisher_url
    INSTALL_DIR_NAME = '{autopf}\Pilipili'
    OUTPUT_BASE_FILENAME = $baseName
    SETUP_ICON_FILE = Join-Path $workspace $config.setup_icon_file
    PRIVILEGES_REQUIRED = $config.privileges_required
    EXECUTABLE_NAME = 'pilipili.exe'
    SOURCE_DIR = $bundle
}
$source = Get-Content (Join-Path $workspace 'windows/packaging/exe/inno_setup.iss') -Raw
foreach ($key in $values.Keys) { $source = $source.Replace("{{$key}}", $values[$key]) }
if ($source -match '\{\{[A-Z_]+\}\}') { throw 'Unresolved Inno Setup template field' }
$compiler = (Get-Command $InnoCompiler -ErrorAction Stop).Source
$languages = Join-Path (Split-Path $compiler -Parent) 'Languages'
Copy-Item (Join-Path $workspace 'windows/packaging/exe/ChineseSimplified.isl') $languages
$script = Join-Path $workspace '.fvm/Pilipili-release.iss'
[IO.File]::WriteAllText($script, $source, [Text.UTF8Encoding]::new($false))
& $compiler ('/O' + (Join-Path $workspace 'dist')) $script
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed' }
$installer = Join-Path $workspace "dist/$baseName.exe"
$sha = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
"$sha  $baseName.exe" | Set-Content -LiteralPath "$installer.sha256" -Encoding ascii
Write-Host "Installer: $installer"
