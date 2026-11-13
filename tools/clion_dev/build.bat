@echo off
REM One-shot MSVC/Ninja build for CLion development.
REM Usage: tools\clion_dev\build.bat [debug|release]
setlocal EnableExtensions

set "ROOT=%~dp0..\.."
pushd "%ROOT%" || exit /b 1
set "ROOT=%CD%"

REM Blender's .gitignore ignores "CMakePresets.json" in ANY directory, so a
REM version-controlled master copy lives under tools\clion_dev\. Restore the
REM root file if it was wiped by git clean or a fresh clone.
if not exist "%ROOT%\CMakePresets.json" (
  echo [!] Restoring root CMakePresets.json from tools\clion_dev\clion_presets.json
  copy /Y "%ROOT%\tools\clion_dev\clion_presets.json" "%ROOT%\CMakePresets.json" >nul
)

set "CMAKE_EXE=D:\Program Files\JetBrains\CLion 2024.3.4\bin\cmake\win\x64\bin\cmake.exe"
if defined BLENDER_CMAKE set "CMAKE_EXE=%BLENDER_CMAKE%"

REM Release is the default: Blender enables WITH_WINDOWS_RELEASE_PDB by default,
REM so breakpoints still work, while compile time and runtime are far better.
REM Pass "debug" for an unoptimized /ZI build.
if /I "%~1"=="debug" (
  set "CFG=clion-msvc-debug"
  set "BUILD=build-debug"
) else (
  set "CFG=clion-msvc-release"
  set "BUILD=build-release"
)

if not exist "%CMAKE_EXE%" (
  echo [!] CMake not found: %CMAKE_EXE%
  echo     Set BLENDER_CMAKE to your cmake.exe and retry.
  popd & exit /b 1
)

REM The MSVC environment must be live for the whole session, including the
REM build step (cl.exe reads INCLUDE/LIB from the environment).
set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat"
if exist "%VCVARS%" (
  echo [0/3] Loading MSVC x64 environment...
  call "%VCVARS%" x64
) else (
  echo [!] vcvarsall.bat not found; falling back to CMakePresets environment.
)

echo [1/3] Preparing build-time data files...
python "%ROOT%\tools\clion_dev\prepare_data.py"
if errorlevel 1 (
  echo [!] prepare_data.py failed.
  popd & exit /b 1
)

echo [2/3] Configuring preset: %CFG%
"%CMAKE_EXE%" --preset %CFG%
if errorlevel 1 (
  echo [!] CMake configure failed.
  popd & exit /b 1
)

echo [3/3] Building + installing ^(12 jobs; target=install copies DLLs^)...
"%CMAKE_EXE%" --build --preset %BUILD%
if errorlevel 1 (
  echo [!] Build failed. Re-run this script to continue incrementally.
  popd & exit /b 1
)

echo [OK] Build finished. Run: tools\clion_dev\run_debug.bat --factory-startup --debug
popd
endlocal
