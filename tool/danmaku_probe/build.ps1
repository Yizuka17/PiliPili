param([switch]$Launch, [string]$AccountFile = '')
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sdk = Join-Path $workspace '.fvm/flutter_sdk'
$project = Join-Path $workspace '.fvm/danmaku_probe'
$version = (Get-Content (Join-Path $workspace '.fvmrc') -Raw | ConvertFrom-Json).flutter
$cmake = Join-Path $workspace '.fvm/cmake/cmake-3.31.10-windows-x86_64/bin/cmake.exe'
$oldLocation = Get-Location
$envNames = @('PUB_CACHE','FLUTTER_ROOT','PATH','PILI_PORTABLE_CMAKE','PILI_VS_VERSION')
$previousEnv = @{}
foreach ($name in $envNames) { $previousEnv[$name] = [Environment]::GetEnvironmentVariable($name) }
function Invoke-Checked([scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Command failed: $LASTEXITCODE" }
}
function Apply-Patch([string]$Directory, [string]$Patch) {
    $previousCeiling = $env:GIT_CEILING_DIRECTORIES
    Push-Location $Directory
    try {
        $env:GIT_CEILING_DIRECTORIES = (Split-Path $Directory -Parent).Replace('\', '/')
        git apply --reverse --check $Patch 2>$null
        if ($LASTEXITCODE -eq 0) { return }
        Invoke-Checked { git apply $Patch }
    } finally { $env:GIT_CEILING_DIRECTORIES = $previousCeiling; Pop-Location }
}
try {
    if (-not (Test-Path -LiteralPath (Join-Path $sdk 'bin/flutter.bat'))) {
        throw 'First provision the project-pinned SDK at .fvm/flutter_sdk.'
    }
    if (-not (Test-Path -LiteralPath $cmake)) { throw 'Project portable CMake 3.31.10 is required.' }
    $revision = (git -C $sdk rev-parse HEAD).Trim()
    $tagRevision = (git -C $sdk rev-parse "refs/tags/$version").Trim()
    if ($revision -ne $tagRevision) { throw "SDK must match .fvmrc ($version)." }
    $env:PUB_CACHE = Join-Path $workspace '.fvm/pub-cache'
    $env:FLUTTER_ROOT = $sdk
    $env:PILI_PORTABLE_CMAKE = $cmake
    $env:PILI_VS_VERSION = '[17.0,18.0)'
    $env:PATH = "$(Join-Path $sdk 'bin');$env:PATH"
    $toolPatch = Join-Path $workspace 'tool/patches/flutter_portable_cmake.patch'
    git -C $sdk apply --reverse --check $toolPatch 2>$null
    $toolPatchAlreadyApplied = $LASTEXITCODE -eq 0
    Apply-Patch $sdk $toolPatch
    # Regenerate the tool snapshot after the same portable-CMake patch as the
    # project's Windows build. Only a disposable SDK cache file is removed.
    $snapshot = Join-Path $sdk 'bin/cache/flutter_tools.snapshot'
    $snapshotStamp = Join-Path $sdk 'bin/cache/flutter_tools.stamp'
    if (-not $toolPatchAlreadyApplied) {
        if (Test-Path -LiteralPath $snapshot) { Remove-Item -LiteralPath $snapshot }
        if (Test-Path -LiteralPath $snapshotStamp) { Remove-Item -LiteralPath $snapshotStamp }
    }
    Invoke-Checked { flutter --version }
    $info = flutter --version --machine | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $info.frameworkVersion -ne $version) { throw 'Flutter version verification failed.' }

    # Use exactly the SDK patch list selected by lib/scripts/patch.ps1 for Windows.
    # Read it without running its package-download/source-rewrite side effects.
    $patchScript = [IO.File]::ReadAllText((Join-Path $workspace 'lib/scripts/patch.ps1'))
    $pathByVariable = @{}
    foreach ($match in [regex]::Matches($patchScript, '(?m)^\$(\w+)\s*=\s*"(lib/scripts/[^"\r\n]+\.patch)"')) {
        $pathByVariable[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    $sdkPatchList = [regex]::Match($patchScript, '\$patches\s*=\s*@\((.*?)\)', 'Singleline').Groups[1].Value
    if (-not $sdkPatchList) { throw 'Project SDK patch list not found.' }
    foreach ($variable in [regex]::Matches($sdkPatchList, '\$(\w+)')) {
        $relative = $pathByVariable[$variable.Groups[1].Value]
        if (-not $relative) { throw 'Project patch variable could not be resolved.' }
        $patch = Join-Path $workspace $relative
        $beta = Join-Path $workspace ('lib/scripts/beta/' + (Split-Path $patch -Leaf))
        if ($version -eq '3.49.0-0.2.pre' -and (Test-Path -LiteralPath $beta)) { $patch = $beta }
        Apply-Patch $sdk $patch
    }
    if (-not (Test-Path -LiteralPath (Join-Path $project 'windows'))) {
        Invoke-Checked { flutter create --platforms=windows --empty --project-name pilipili_danmaku_probe $project }
    }
    $coreSource = Join-Path $workspace '.fvm/player_sources/core'
    $videoSource = Join-Path $workspace '.fvm/player_sources/video'
    $playerSources = @(
        @{Path=$coreSource; Url='https://github.com/My-Responsitories/media-kit.git'; Sha='73771ec38176be2d984a3049c28177bce23b54a0'},
        @{Path=$videoSource; Url='https://github.com/bggRGjQaUbCoE/media-kit.git'; Sha='fd8421d21eade4d6d12de137fa7df902fec20292'}
    )
    foreach ($source in $playerSources) {
        if (-not (Test-Path -LiteralPath (Join-Path $source.Path '.git'))) {
            Invoke-Checked { git clone --depth 1 --branch native $source.Url $source.Path }
        }
        if ((git -C $source.Path rev-parse HEAD).Trim() -ne $source.Sha) {
            throw 'Player dependency checkout must match the root lockfile revision.'
        }
    }
    # Pub's default mirror clone downloads all repository history. Use the exact
    # locked commits checked above as path dependencies in the generated project.
    $probeSpec = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'pubspec.yaml'))
    $dependencyPattern = '(?m)^  (media_kit\w*):\r?\n    git:\r?\n      url: ([^\r\n]+)\r?\n      path: ([^\r\n]+)\r?\n      ref: ([^\r\n]+)'
    $probeSpec = [regex]::Replace($probeSpec, $dependencyPattern, {
        param($match)
        $checkout = if ($match.Groups[2].Value -like '*My-Responsitories*') { $coreSource } else { $videoSource }
        $dependencyPath = (Join-Path $checkout $match.Groups[3].Value).Replace('\','/')
        '  ' + $match.Groups[1].Value + ":`n    path: " + $dependencyPath
    })
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), $probeSpec)
    Copy-Item -LiteralPath (Join-Path $workspace 'pubspec.lock') -Destination $project -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'lib') -Destination $project -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'checks') -Destination $project -Recurse -Force
    [IO.File]::WriteAllText((Join-Path $project 'analysis_options.yaml'), "analyzer:`n  exclude: [build/**]`n")
    $mainCpp = Join-Path $project 'windows/runner/main.cpp'
    $mainSource = [IO.File]::ReadAllText($mainCpp)
    $mainSource = $mainSource.Replace('1280, 720', '1120, 920').Replace('L"pilipili_danmaku_probe"', 'L"Pilipili Danmaku - Flutter Test"')
    [IO.File]::WriteAllText($mainCpp, $mainSource)
    Set-Location $project
    Invoke-Checked { flutter pub get }
    # Match the project's material_ui patches, using normalized temporary copies
    # instead of modifying the repository's patch files.
    $material = Get-Item (Join-Path $env:PUB_CACHE 'hosted/pub.dev/material_ui-1.5.0')
    foreach ($name in @('modal_barrier_material','navigation_drawer','popup_menu','fab','text_field','scaffold','refresh_indicator','tabs','hover_highlight')) {
        $source = Join-Path $workspace "lib/scripts/material/$name.patch"
        $normalized = Join-Path $project "$name.patch"
        [IO.File]::WriteAllText($normalized, [IO.File]::ReadAllText($source).Replace("`r`n", "`n"))
        Apply-Patch $material.FullName $normalized
    }
    Invoke-Checked { dart format lib checks }
    Invoke-Checked { flutter analyze --no-pub }
    Invoke-Checked { flutter test --no-pub checks }
    Invoke-Checked { flutter build windows --release --no-pub }
    $bundle = Join-Path $project 'build/windows/x64/runner/Release'
    # Reuse app-local MSVC release runtime DLLs from the same installed toolchain.
    $redistRoot = 'C:/zako/VSBuildTools2022/App/VC/Redist/MSVC'
    $redist = Get-ChildItem -LiteralPath $redistRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    $crt = Get-ChildItem -Path (Join-Path $redist.FullName 'x64/Microsoft.VC*.CRT') -Directory | Select-Object -First 1
    if ($crt) { Get-ChildItem -LiteralPath $crt.FullName -Filter '*.dll' -File | Copy-Item -Destination $bundle }
    $manifest = @{ flutter = $info.frameworkVersion; framework = $info.frameworkRevision; engine = $info.engineRevision;
        builtAt = [DateTimeOffset]::UtcNow.ToString('o'); samples = @('BV11d6rB4Evy','BV1dS421w7Bf','BV1rP41137E6');
        projectSdkPatches = @(git -C $sdk diff --name-only); accountEmbedded = $false; automaticSubmission = $false }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $bundle 'probe-build.json') -Encoding utf8
    Write-Output "Executable: $(Join-Path $bundle 'pilipili_danmaku_probe.exe')"
    if ($Launch) {
        $launchArgs = if ($AccountFile) { '"' + $AccountFile + '"' } else { $null }
        if ($launchArgs) { Start-Process -FilePath (Join-Path $bundle 'pilipili_danmaku_probe.exe') -ArgumentList $launchArgs -WorkingDirectory $bundle -WindowStyle Normal }
        else { Start-Process -FilePath (Join-Path $bundle 'pilipili_danmaku_probe.exe') -WorkingDirectory $bundle -WindowStyle Normal }
    }
} finally {
    Set-Location $oldLocation
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $previousEnv[$name]) }
}
