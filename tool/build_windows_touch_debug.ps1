param(
    [switch]$PortableCMake,
    [switch]$SkipChecks,
    [switch]$Production,
    [string]$ArtifactSuffix = '',
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'debug'
)

if ($ArtifactSuffix -and $ArtifactSuffix -notmatch '^[a-zA-Z0-9-]+$') {
    throw 'ArtifactSuffix must contain only letters, digits, and hyphens'
}

$ErrorActionPreference = 'Stop'
if ($Production -and $Mode -ne 'release') { throw 'Production requires release mode' }
$workspace = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $workspace '.fvm/flutter_sdk'
$version = (Get-Content (Join-Path $workspace '.fvmrc') -Raw | ConvertFrom-Json).flutter
$oldLocation = Get-Location
$envNames = @('PATH', 'FLUTTER_ROOT', 'PUB_CACHE', 'GITHUB_WORKSPACE', 'GITHUB_ENV',
              'PILI_PORTABLE_CMAKE', 'PILI_VS_VERSION', 'PILI_FLUTTER_BETA_PATCHES')
$previousEnv = @{}
foreach ($name in $envNames) { $previousEnv[$name] = [Environment]::GetEnvironmentVariable($name) }
$pubspecPath = Join-Path $workspace 'pubspec.yaml'
$originalPubspec = [IO.File]::ReadAllText($pubspecPath)

function Invoke-Checked([scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
}

try {
    Set-Location $workspace
    if (-not (Test-Path -LiteralPath (Join-Path $sdk 'bin/flutter.bat'))) {
        Invoke-Checked { git clone --depth 1 --branch $version https://github.com/flutter/flutter.git $sdk }
    }
    $sdkRevision = (git -C $sdk rev-parse HEAD).Trim()
    $tagRevision = (git -C $sdk rev-parse "refs/tags/$version").Trim()
    if ($LASTEXITCODE -ne 0 -or $sdkRevision -ne $tagRevision) {
        throw "SDK must be checked out at $version. Use a dedicated SDK; do not reset a shared checkout."
    }
    $env:FLUTTER_ROOT = $sdk
    $env:PUB_CACHE = Join-Path $workspace '.fvm/pub-cache'
    $env:GITHUB_WORKSPACE = $workspace
    $env:GITHUB_ENV = Join-Path $workspace '.fvm/build-env.txt'
    $env:PATH = "$sdk\bin;$env:PATH"
    $env:PILI_FLUTTER_BETA_PATCHES = '1'

    $toolsDir = Join-Path $workspace '.fvm/tools'
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    $env:PATH = "$toolsDir;$env:PATH"
    if (-not (Get-Command nuget.exe -ErrorAction SilentlyContinue)) {
        $nuget = Join-Path $toolsDir 'nuget.exe'
        Invoke-WebRequest 'https://dist.nuget.org/win-x86-commandline/v6.14.0/nuget.exe' -OutFile $nuget
        if ((Get-AuthenticodeSignature -LiteralPath $nuget).Status -ne 'Valid') {
            throw 'NuGet signature validation failed'
        }
    }

    # Keep native package sources local to the build. Some VS Build Tools
    # installations configure only the offline feed in the user's NuGet config.
    $nativeBuildDir = Join-Path $workspace 'build/windows/x64'
    New-Item -ItemType Directory -Path $nativeBuildDir -Force | Out-Null
    $nugetConfig = Join-Path $nativeBuildDir 'NuGet.Config'
    [IO.File]::WriteAllText($nugetConfig, @'
<?xml version="1.0" encoding="utf-8"?>
<configuration><packageSources><clear /><add key="nuget.org" value="https://api.nuget.org/v3/index.json" /></packageSources></configuration>
'@, [Text.UTF8Encoding]::new($false))

    # Optional for hosts with MSVC/Windows SDK installed but no VS CMake component.
    if ($PortableCMake) {
        $cmakeVersion = '3.31.10'
        $cmakeRoot = Join-Path $workspace '.fvm/cmake'
        $cmake = Join-Path $cmakeRoot "cmake-$cmakeVersion-windows-x86_64/bin/cmake.exe"
        if (-not (Test-Path -LiteralPath $cmake)) {
            $downloadDir = Join-Path $workspace '.fvm/downloads'
            New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
            $archiveName = "cmake-$cmakeVersion-windows-x86_64.zip"
            $archive = Join-Path $downloadDir $archiveName
            $baseUrl = "https://github.com/Kitware/CMake/releases/download/v$cmakeVersion"
            Invoke-WebRequest "$baseUrl/$archiveName" -OutFile $archive
            $checksums = (Invoke-WebRequest "$baseUrl/cmake-$cmakeVersion-SHA-256.txt").Content
            if ($checksums -is [byte[]]) { $checksums = [Text.Encoding]::UTF8.GetString($checksums) }
            $expected = (($checksums -split "`n" | Where-Object { $_.TrimEnd().EndsWith($archiveName) }) -split '\s+')[0]
            if (-not $expected -or (Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant() -ne $expected) {
                throw 'CMake archive checksum mismatch'
            }
            Expand-Archive -LiteralPath $archive -DestinationPath $cmakeRoot -Force
        }
        $env:PILI_PORTABLE_CMAKE = $cmake
        $env:PILI_VS_VERSION = '[17.0,18.0)'
        $toolPatch = Join-Path $PSScriptRoot 'patches/flutter_portable_cmake.patch'
        git -C $sdk apply --reverse --check $toolPatch 2>$null
        if ($LASTEXITCODE -ne 0) {
            Invoke-Checked { git -C $sdk apply $toolPatch }
            $snapshot = Join-Path $sdk 'bin/cache/flutter_tools.snapshot'
            if (Test-Path -LiteralPath $snapshot) { Remove-Item -LiteralPath $snapshot }
        }
    }

    Invoke-Checked { flutter --version }
    $flutterInfo = flutter --version --machine | ConvertFrom-Json
    if ($flutterInfo.frameworkVersion -ne $version) { throw 'Unexpected Flutter version' }
    $engineSource = Join-Path $sdk 'engine/src/flutter/shell/platform/windows/flutter_window.cc'
    if (-not ([IO.File]::ReadAllText($engineSource).Contains('buttons != 0 && GetCapture() != window_handle_'))) {
        throw 'SDK does not contain the Flutter #190029 input fix'
    }

    # Same prebuild metadata and framework/UI patches as the Windows release workflow.
    & (Join-Path $workspace 'lib/scripts/build.ps1')
    if (-not (Test-Path -LiteralPath 'pili_release.json')) { throw 'Build metadata missing' }
    & (Join-Path $workspace 'lib/scripts/patch.ps1') windows
    Set-Location $workspace

    if (-not $SkipChecks) {
        Invoke-Checked { dart analyze lib/services lib/common/widgets/scale_app.dart lib/common/widgets/gesture/mouse_interactive_viewer.dart lib/common/widgets/gesture/touch_diagnostic_ink_well.dart lib/common/widgets/video_card/video_card_h.dart lib/common/widgets/video_card/video_card_v.dart lib/plugin/pl_player/view/view.dart lib/plugin/pl_player/controller.dart lib/main.dart lib/pages/video/reply/widgets/reply_item_grpc.dart lib/pages/about/view.dart lib/utils/storage_pref.dart lib/utils/storage_key.dart }
        Invoke-Checked { flutter test test/services test/utils/accounts/deleted_account_test.dart }
    }
    $flutterVersionDefine = 'pili.flutter=' + $flutterInfo.frameworkVersion
    $engineDefine = 'pili.engine=' + $flutterInfo.engineRevision
    $touchLogDefine = 'pili.touchLog=' + (-not $Production).ToString().ToLowerInvariant()
    Invoke-Checked {
        flutter build windows "--$Mode" --no-pub --dart-define-from-file=pili_release.json `
            --dart-define=$touchLogDefine --dart-define=$flutterVersionDefine --dart-define=$engineDefine
    }

    $configuration = if ($Mode -eq 'debug') { 'Debug' } else { 'Release' }
    $bundle = Join-Path $workspace "build/windows/x64/runner/$configuration"
    if (-not $SkipChecks) {
        $cmakeCache = Get-Content (Join-Path $nativeBuildDir 'CMakeCache.txt')
        $cmakeForTests = (($cmakeCache | Where-Object { $_.StartsWith('CMAKE_COMMAND:INTERNAL=') }) -split '=', 2)[1]
        $testGenerator = (($cmakeCache | Where-Object { $_.StartsWith('CMAKE_GENERATOR:INTERNAL=') }) -split '=', 2)[1]
        $testInstance = (($cmakeCache | Where-Object { $_.StartsWith('CMAKE_GENERATOR_INSTANCE:INTERNAL=') }) -split '=', 2)[1]
        $nativeTests = Join-Path $workspace '.fvm/native-touch-tests'
        Invoke-Checked {
            & $cmakeForTests -S (Join-Path $PSScriptRoot 'tests') -B $nativeTests `
                -G $testGenerator -A x64 "-DCMAKE_GENERATOR_INSTANCE=$testInstance"
        }
        Invoke-Checked { & $cmakeForTests --build $nativeTests --config $configuration }
        Invoke-Checked { & (Join-Path $nativeTests "$configuration/windows_touch_input_test.exe") }
    }
    $runtimeFiles = @()
    $omittedLibraries = @()
    if ($Mode -eq 'release') {
        # App-local release CRT deployment allows testing without Visual Studio.
        # Never bundle Microsoft's non-redistributable debug runtime DLLs.
        $instanceLine = Get-Content (Join-Path $nativeBuildDir 'CMakeCache.txt') |
            Where-Object { $_.StartsWith('CMAKE_GENERATOR_INSTANCE:INTERNAL=') } |
            Select-Object -First 1
        $vsInstance = ($instanceLine -split '=', 2)[1]
        $redistRoot = Join-Path $vsInstance 'VC/Redist/MSVC'
        $redist = Get-ChildItem -LiteralPath $redistRoot -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        $crt = Get-ChildItem -Path (Join-Path $redist.FullName 'x64/Microsoft.VC*.CRT') -Directory |
            Select-Object -First 1
        if (-not $crt) { throw 'MSVC x64 redistributable runtime directory missing' }
        $runtimeFiles = @(Get-ChildItem -LiteralPath $crt.FullName -Filter '*.dll' -File)
        if (-not $runtimeFiles) { throw 'MSVC runtime DLLs missing' }
        foreach ($file in $runtimeFiles) { Copy-Item -LiteralPath $file.FullName -Destination $bundle }

        # ANGLE ships an unused debug zlib DLL. Its other binaries statically
        # link zlib. Verify no bundled binary references it before omitting it.
        $unusedZlib = Join-Path $bundle 'zlib.dll'
        if (Test-Path -LiteralPath $unusedZlib) {
            foreach ($binary in (Get-ChildItem -LiteralPath $bundle -File |
                Where-Object { $_.Extension -in '.exe', '.dll' -and $_.Name -ne 'zlib.dll' })) {
                $bytes = [IO.File]::ReadAllBytes($binary.FullName)
                if ([Text.Encoding]::ASCII.GetString($bytes).ToLowerInvariant().Contains('zlib.dll') -or
                    [Text.Encoding]::Unicode.GetString($bytes).ToLowerInvariant().Contains('zlib.dll')) {
                    throw "Cannot omit zlib.dll: referenced by $($binary.Name)"
                }
            }
            Remove-Item -LiteralPath $unusedZlib
            $omittedLibraries = @('zlib.dll')
        }
    }
    $outputDir = Join-Path $workspace 'dist'
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $manifest = @{
        mode = $Mode; flutter = $flutterInfo.frameworkVersion
        framework = $flutterInfo.frameworkRevision; engine = $flutterInfo.engineRevision
        touchFix = 'https://github.com/flutter/flutter/pull/190029'
        appCommit = (git rev-parse HEAD).Trim(); builtAt = [DateTimeOffset]::UtcNow.ToString('o')
        workingTreeDirty = [bool](git status --porcelain)
        logDirectory = '%TEMP%\Pilipili-touch-logs'
        runtimeFiles = @($runtimeFiles | ForEach-Object { $_.Name })
        omittedUnusedLibraries = $omittedLibraries
        nativeTouchPolicy = 'disable-windows-press-and-hold-on-parent-and-flutter-view'
        touchHoverPolicy = 'clear-on-touch-and-activation-await-fresh-mouse'
        diagnosticRevision = 'v4'
        touchLoggingEnabled = -not $Production
        cursorDiagnostics = 'visibility-suppression-position-and-widget-states'
        projectPatches = @((git -C $sdk diff --name-only) | Where-Object { $_ -ne 'packages/flutter_tools/lib/src/windows/visual_studio.dart' })
    }
    $metadata = Get-Content 'pili_release.json' -Raw | ConvertFrom-Json
    $manifest.appVersion = $metadata.'pili.name' + '+' + $metadata.'pili.code'
    $manifestName = if ($Production) { 'release-build.json' } else { 'touch-debug-build.json' }
    if ($Production) {
        foreach ($oldName in @('piliplus.exe', 'touch-debug-build.json', 'collect_touch_logs.ps1', 'WINDOWS_TOUCH_DEBUG.md')) {
            $oldFile = Join-Path $bundle $oldName
            if (Test-Path -LiteralPath $oldFile -PathType Leaf) { Remove-Item -LiteralPath $oldFile }
        }
    } else {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'collect_touch_logs.ps1') -Destination $bundle
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'WINDOWS_TOUCH_DEBUG.md') -Destination $bundle
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $bundle $manifestName) -Encoding utf8
    $suffix = if ($ArtifactSuffix) { "-$ArtifactSuffix" } else { '' }
    $zipName = if ($Production) { "Pilipili_windows_$($manifest.appVersion)_x64_portable.zip" } else { "Pilipili-Windows-touch-$Mode-flutter-$version$suffix.zip" }
    $zip = Join-Path $outputDir $zipName
    Compress-Archive -Path "$bundle/*" -DestinationPath $zip -Force
    $sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$sha  $([IO.Path]::GetFileName($zip))" | Set-Content -LiteralPath "$zip.sha256" -Encoding ascii
    Write-Host "Diagnostic executable ($Mode): $bundle\pilipili.exe"
    Write-Host "Diagnostic bundle ($Mode): $zip"
    Write-Host 'Logs: %TEMP%\Pilipili-touch-logs'
}
finally {
    [IO.File]::WriteAllText($pubspecPath, $originalPubspec, [Text.UTF8Encoding]::new($false))
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $previousEnv[$name]) }
    Set-Location $oldLocation
}
