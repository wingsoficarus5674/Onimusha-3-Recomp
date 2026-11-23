@echo off
rem Step 4: copy generated C++ into the runtime and build ps2EntryRunner.exe (the native PC executable).
rem Everything printed is also saved to build\4_build_runtime_output.txt
setlocal
cd /d "%~dp0"
if "%~1"=="__run" goto run
if not exist build mkdir build
powershell -NoProfile -Command "cmd /c 'call %~nx0 __run %~1 2>&1' | Tee-Object -FilePath 'build\4_build_runtime_output.txt'"
pause
exit /b

:run
if not exist output\register_functions.cpp (echo Run 3_recompile.bat first. & exit /b 1)
set "RT=tools\PS2Recomp\ps2xRuntime"
rem Sync generated files: copy only changed ones (keeps incremental builds fast) and remove stale .cpp
echo Syncing generated sources (a minute or two)...
powershell -NoProfile -ExecutionPolicy Bypass -File sync_generated.ps1 -Src output -Dst "%RT%\src\runner" -Filter *.cpp -Prune
if errorlevel 1 (echo Sync FAILED. & exit /b 1)
powershell -NoProfile -ExecutionPolicy Bypass -File sync_generated.ps1 -Src output -Dst "%RT%\include" -Filter ps2_recompiled_functions.h
if errorlevel 1 (echo Sync FAILED. & exit /b 1)
rem Recompiled code overlays from 3b_recompile_overlays.bat
if not exist "%RT%\src\runner_overlays" mkdir "%RT%\src\runner_overlays"
if not exist output_overlays goto nooverlays
powershell -NoProfile -ExecutionPolicy Bypass -File sync_generated.ps1 -Src output_overlays -Dst "%RT%\src\runner_overlays" -Filter *.cpp -Prune
if errorlevel 1 (echo Sync FAILED. & exit /b 1)
goto overlaysdone
:nooverlays
echo NOTE: output_overlays\ not found. Run 3b_recompile_overlays.bat first, otherwise the game
echo       stops right after the CAPCOM logo.
:overlaysdone
rem ps2_recompiled_stubs.h only repeats declarations from ps2_recompiled_functions.h; a fixed copy
rem means a new stub binding rebuilds a few files instead of all ~64,000
powershell -NoProfile -ExecutionPolicy Bypass -File sync_generated.ps1 -Src patches -Dst "%RT%\include" -Filter ps2_recompiled_stubs.h
if errorlevel 1 (echo Sync FAILED. & exit /b 1)
rem Apply this project's fixes to PS2Recomp (skips any already applied)
for %%P in (patches\*.patch) do (
  git apply --reverse --check --directory=tools/PS2Recomp "%%P" >nul 2>&1 || git apply --directory=tools/PS2Recomp "%%P" || (echo Failed to apply %%P & exit /b 1)
)
rem Per-function trace logging (ps2_log.txt) makes the game very slow. Off by default;
rem run "4_build_runtime.bat trace" to turn it on for debugging. Switching either way rebuilds everything.
set "TRACE=OFF"
if /i "%~2"=="trace" set "TRACE=ON"
cmake -S tools\PS2Recomp -B build\runtime -DPS2X_BUILD_RECOMP=OFF -DPS2X_BUILD_ANALYZER=OFF -DPS2X_BUILD_TEST=OFF -DPS2X_BUILD_STUDIO=OFF -DPS2X_ENABLE_AGRESSIVE_LOGS=%TRACE%
if errorlevel 1 (echo CMake configure FAILED. & exit /b 1)
cmake --build build\runtime --config Release --parallel --target ps2EntryRunner
if errorlevel 1 (echo. & echo BUILD FAILED - search build\4_build_runtime_output.txt for "error". & exit /b 1)
echo.
echo Built. Run with: 5_run.bat
exit /b 0
