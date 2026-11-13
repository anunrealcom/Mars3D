<#
    Blender build helper (invoked from .vscode/tasks.json).

    Usage:
      powershell -NoProfile -ExecutionPolicy Bypass -File .vscode/build.ps1 -BuildDir build_clion -Config Debug
      ... -Install     ensure the runtime files (scripts / datafiles / python / DLLs / CRT and
                       "blender.shared" manifest) exist in <build-dir>\bin, running
                       "ninja install" only when they are missing.
      ... -ForceInstall re-run "ninja install" even when the runtime already looks complete.
      ... -Configure    re-run the CMake configure step (also writes compile_commands.json).

    NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less scripts as ANSI,
          which corrupts non-ASCII characters and breaks parsing.
#>
[CmdletBinding()]
param(
    [string]$BuildDir = 'build_clion',
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo')]
    [string]$Config = 'Debug',
    [switch]$Configure,
    [switch]$Install,
    [switch]$ForceInstall,
    [int]$Jobs = 0,
    [string]$Target = ''
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$buildPath = Join-Path $root $BuildDir
$cacheFile = Join-Path $buildPath 'CMakeCache.txt'

function Find-Tool {
    param([string]$Name, [string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# cmake is not on PATH here, so prefer the CLion bundled copies.
$clionRoots = @()
foreach ($base in @("$env:ProgramFiles\JetBrains", 'D:\Program Files\JetBrains', "${env:ProgramFiles(x86)}\JetBrains")) {
    if ($base -and (Test-Path -LiteralPath $base)) {
        $clionRoots += @(Get-ChildItem -LiteralPath $base -Directory -Filter 'CLion*' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName })
    }
}

$cmakeCandidates = @()
$ninjaCandidates = @()
foreach ($clionRoot in $clionRoots) {
    $cmakeCandidates += (Join-Path $clionRoot 'bin\cmake\win\x64\bin\cmake.exe')
    $ninjaCandidates += (Join-Path $clionRoot 'bin\ninja\win\x64\ninja.exe')
}
$cmakeCandidates += @(
    'C:\Program Files\CMake\bin\cmake.exe',
    'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
)

$cmakeExe = Find-Tool 'cmake' $cmakeCandidates
if (-not $cmakeExe) {
    throw 'cmake.exe not found. Install CMake, or Visual Studio 2022 / CLion (which bundle it).'
}
$ninjaExe = Find-Tool 'ninja' $ninjaCandidates

if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Environment]::ProcessorCount)
}

# Ninja + MSVC needs the INCLUDE / LIB environment of the "x64 Native Tools" shell,
# otherwise cl.exe cannot even find <climits> or <float.h>.
function Import-MsvcEnvironment {
    $vsPath = $null
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $vsPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath |
            Select-Object -First 1)
    }
    if (-not $vsPath) {
        foreach ($candidate in @(
                'C:\Program Files\Microsoft Visual Studio\2022\Community',
                'C:\Program Files\Microsoft Visual Studio\2022\Professional',
                'C:\Program Files\Microsoft Visual Studio\2022\Enterprise',
                'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community')) {
            if (Test-Path -LiteralPath $candidate) { $vsPath = $candidate; break }
        }
    }
    if (-not $vsPath) {
        Write-Warning 'Visual Studio (MSVC toolchain) not found, system headers may be missing.'
        return
    }
    $vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path -LiteralPath $vcvars)) {
        Write-Warning "vcvars64.bat not found: $vcvars"
        return
    }

    $envDump = & cmd.exe /c "`"$vcvars`" >nul 2>&1 && set"
    foreach ($line in $envDump) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) {
            $name = $line.Substring(0, $separator)
            $value = $line.Substring($separator + 1)
            Set-Item -Path "env:$name" -Value $value -ErrorAction SilentlyContinue
        }
    }
    Write-Host " MSVC      : $vsPath" -ForegroundColor DarkGray
}

function Test-BlenderRuntime {
    param([string]$Path)
    $required = @(
        'bin\mars3d.exe',
        'bin\blender.crt\blender.crt.manifest',
        'bin\blender.shared\blender.shared.manifest',
        'bin\5.3\datafiles\colormanagement\config.ocio',
        'bin\5.3\scripts\startup\bl_ui\__init__.py',
        'bin\5.3\scripts\modules\bpy\__init__.py'
    )
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $relative))) { return $false }
    }
    return $true
}

# `ninja install` may abort halfway through (missing Git LFS assets, see note above),
# which leaves the "blender.shared" assembly without its manifest. Copying it makes the
# executable start again.
function Repair-SharedManifest {
    param([string]$Path, [string]$ConfigName)
    $target = Join-Path $Path 'bin\blender.shared\blender.shared.manifest'
    if (Test-Path -LiteralPath $target) { return }
    $source = Join-Path $Path "$ConfigName\blender.shared.manifest"
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $target -Force
        Write-Host "Patched : $target" -ForegroundColor DarkGray
    }
}

Import-MsvcEnvironment

Write-Host '=========================================================' -ForegroundColor DarkCyan
Write-Host " Build dir : $buildPath" -ForegroundColor Cyan
Write-Host " Build type: $Config" -ForegroundColor Cyan
Write-Host " CMake     : $cmakeExe" -ForegroundColor DarkGray
if ($ninjaExe) { Write-Host " Ninja     : $ninjaExe" -ForegroundColor DarkGray }
Write-Host " Jobs      : $Jobs" -ForegroundColor DarkGray
Write-Host '=========================================================' -ForegroundColor DarkCyan

$needsConfigure = [bool]$Configure -or (-not (Test-Path -LiteralPath $cacheFile))
if (-not $needsConfigure) {
    $cachedLine = Select-String -LiteralPath $cacheFile -Pattern '^CMAKE_BUILD_TYPE:STRING=(.*)$' |
        Select-Object -First 1
    if ($cachedLine) {
        $cachedType = $cachedLine.Matches[0].Groups[1].Value.Trim()
        if ($cachedType -and ($cachedType -ne $Config)) {
            Write-Warning "Build dir '$BuildDir' was configured with CMAKE_BUILD_TYPE='$cachedType' (requested '$Config')."
            Write-Warning 'Delete that build directory first if you really want to switch build type.'
        }
    }
}

if ($needsConfigure) {
    Write-Host '>> Configuring with CMake ...' -ForegroundColor Yellow
    $cmakeArgs = @(
        '-S', $root,
        '-B', $buildPath,
        '-G', 'Ninja',
        "-DCMAKE_BUILD_TYPE=$Config",
        '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON'
    )
    if ($ninjaExe) { $cmakeArgs += "-DCMAKE_MAKE_PROGRAM=$ninjaExe" }

    & $cmakeExe @cmakeArgs
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed (exit code $LASTEXITCODE)." }
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$runtimeReady = Test-BlenderRuntime -Path $buildPath
$runInstall = $Install -and ($ForceInstall -or (-not $runtimeReady))

$buildArgs = @('--build', $buildPath, '--config', $Config, '--parallel', "$Jobs")
if ($runInstall) {
    $buildArgs += @('--target', 'install')
    Write-Host '>> Building and installing runtime files (ninja install) ...' -ForegroundColor Yellow
}
elseif ($Target) {
    $buildArgs += @('--target', $Target)
    Write-Host ">> Building target '$Target' ..." -ForegroundColor Yellow
}
else {
    if ($Install) {
        Write-Host '>> Building Blender (runtime files already installed, skipping install) ...' -ForegroundColor Yellow
    }
    else {
        Write-Host '>> Building Blender ...' -ForegroundColor Yellow
    }
}

& $cmakeExe @buildArgs
$buildExit = $LASTEXITCODE

if ($buildExit -ne 0) {
    if (-not $runInstall) { throw "Build failed (exit code $buildExit)." }

    # This checkout is missing ~6800 Git LFS objects (the mirror no longer serves them),
    # including release/datafiles/icons/*.dat, so `install` aborts with
    # "file INSTALL cannot find ...". Everything needed to actually run Blender is
    # already there, so patch the manifest and continue when the runtime is usable.
    Repair-SharedManifest -Path $buildPath -ConfigName $Config
    if (Test-BlenderRuntime -Path $buildPath) {
        Write-Warning "install reported errors (missing data files such as release/datafiles/icons), runtime is usable."
    }
    else {
        throw "Build/install failed (exit code $buildExit)."
    }
}

$stopwatch.Stop()
Write-Host ("Build finished in {0:N1} min." -f $stopwatch.Elapsed.TotalMinutes) -ForegroundColor Green

$exePath = Join-Path $buildPath 'bin\mars3d.exe'
if (Test-Path -LiteralPath $exePath) {
    Write-Host "Executable: $exePath" -ForegroundColor Green
}
else {
    Write-Warning "Not found: $exePath (build incomplete or link failed)."
}

if (Test-BlenderRuntime -Path $buildPath) {
    Write-Host "Runtime files ready: $(Join-Path $buildPath 'bin\5.3')" -ForegroundColor Green
}
else {
    Write-Warning "Runtime files incomplete in $(Join-Path $buildPath 'bin'). Run the install task again."
}
