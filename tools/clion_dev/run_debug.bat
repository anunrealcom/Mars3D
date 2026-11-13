@echo off
REM Launch the locally built blender.exe with the source-tree scripts and a
REM complete datafiles folder (borrowed from the installed Blender 5.2 build,
REM since this checkout has no Git LFS objects).
REM Usage: tools\clion_dev\run_debug.bat [--factory-startup --debug ...]
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0..\.."
pushd "%ROOT%" || exit /b 1
set "ROOT=%CD%"

REM `ninja install` writes the fully populated runtime tree into bin\<Config>\.
set "BIN="
if exist "%ROOT%\build_clion_release\bin\Release\blender.exe" set "BIN=%ROOT%\build_clion_release\bin\Release"
if not defined BIN if exist "%ROOT%\build_clion\bin\Debug\blender.exe" set "BIN=%ROOT%\build_clion\bin\Debug"
if not defined BIN if exist "%ROOT%\build_clion\bin\blender.exe" set "BIN=%ROOT%\build_clion\bin"
if not defined BIN if exist "%ROOT%\build_clion_release\bin\blender.exe" set "BIN=%ROOT%\build_clion_release\bin"
if not defined BIN (
  echo [!] No blender.exe found. Run build.bat first.
  popd & exit /b 1
)

set "BLENDER_SYSTEM_SCRIPTS=%ROOT%\scripts"
set "BLENDER_SYSTEM_DATAFILES=C:\Program Files\Blender Foundation\Blender 5.2\5.2\datafiles"
if not exist "%BLENDER_SYSTEM_DATAFILES%" set "BLENDER_SYSTEM_DATAFILES=%ROOT%\release\datafiles"

set "PATH=%BIN%;%ROOT%\lib\windows_x64\python\313\bin;%PATH%"
REM Make every prebuilt dependency DLL discoverable (install usually copies
REM them into BIN, but a partial build may not have run install yet).
for /d %%D in ("%ROOT%\lib\windows_x64\*") do (
  if exist "%%~fD\bin\*.dll" set "PATH=%%~fD\bin;!PATH!"
  if exist "%%~fD\lib\*.dll" set "PATH=%%~fD\lib;!PATH!"
)
REM Debug builds link against the debug CRT, which is not on PATH by default.
for /d %%D in ("C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC\*") do (
  if exist "%%~fD\debug_nonredist\x64\Microsoft.VC143.DebugCRT" set "PATH=%%~fD\debug_nonredist\x64\Microsoft.VC143.DebugCRT;!PATH!"
)

echo [OK] BIN       = %BIN%
echo [OK] SCRIPTS   = %BLENDER_SYSTEM_SCRIPTS%
echo [OK] DATAFILES = %BLENDER_SYSTEM_DATAFILES%
"%BIN%\blender.exe" %*
popd
endlocal
