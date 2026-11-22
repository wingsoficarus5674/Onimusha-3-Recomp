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
rem Remove generated files from any earlier run, then copy the current ones
del /q "%RT%\src\runner\*.cpp" 2>nul
del /q "%RT%\include\ps2_recompiled_functions.h" "%RT%\include\ps2_recompiled_stubs.h" 2>nul
echo Copying generated sources...
copy /y output\*.cpp "%RT%\src\runner\" >nul
copy /y output\*.h   "%RT%\include\" >nul
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
