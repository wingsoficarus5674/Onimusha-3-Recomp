@echo off
rem Step 4: copy generated C++ into the runtime and build ps2EntryRunner.exe (the native PC executable).
rem Everything printed is also saved to build\4_build_runtime_output.txt
setlocal
cd /d "%~dp0"
if "%~1"=="__run" goto run
if not exist build mkdir build
powershell -NoProfile -Command "cmd /c 'call %~nx0 __run 2>&1' | Tee-Object -FilePath 'build\4_build_runtime_output.txt'"
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
rem ps2_recompiled_stubs.h only repeats declarations from ps2_recompiled_functions.h; a fixed copy
rem means a new stub binding rebuilds a few files instead of all ~64,000
powershell -NoProfile -ExecutionPolicy Bypass -File sync_generated.ps1 -Src patches -Dst "%RT%\include" -Filter ps2_recompiled_stubs.h
if errorlevel 1 (echo Sync FAILED. & exit /b 1)
rem Apply this project's fixes to PS2Recomp (skips any already applied)
for %%P in (patches\*.patch) do (
  git apply --reverse --check --directory=tools/PS2Recomp "%%P" >nul 2>&1 || git apply --directory=tools/PS2Recomp "%%P" || (echo Failed to apply %%P & exit /b 1)
)
cmake -S tools\PS2Recomp -B build\runtime -DPS2X_BUILD_RECOMP=OFF -DPS2X_BUILD_ANALYZER=OFF -DPS2X_BUILD_TEST=OFF -DPS2X_BUILD_STUDIO=OFF
if errorlevel 1 (echo CMake configure FAILED. & exit /b 1)
cmake --build build\runtime --config Release --parallel --target ps2EntryRunner
if errorlevel 1 (echo. & echo BUILD FAILED - search build\4_build_runtime_output.txt for "error". & exit /b 1)
echo.
echo Built. Run with: 5_run.bat
exit /b 0
