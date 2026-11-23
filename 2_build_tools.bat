@echo off
rem Step 2: build ps2_recomp.exe and ps2_analyzer.exe from tools\PS2Recomp.
rem Needs: Visual Studio 2022 (Desktop development with C++), CMake 3.21+, Git (CMake fetches dependencies).
setlocal
cd /d "%~dp0"
where cmake >nul 2>&1 || (echo CMake not found on PATH. Install from https://cmake.org/download/ & pause & exit /b 1)
where git   >nul 2>&1 || (echo Git not found on PATH. Install from https://git-scm.com/download/win & pause & exit /b 1)

rem Apply this project's fixes to PS2Recomp (each once; the list is kept in tools\PS2Recomp)
powershell -NoProfile -ExecutionPolicy Bypass -File apply_patches.ps1
if errorlevel 1 (echo Patching PS2Recomp FAILED. & pause & exit /b 1)
cmake -S tools\PS2Recomp -B build\tools -DPS2X_BUILD_RUNTIME=OFF -DPS2X_BUILD_TEST=OFF -DPS2X_BUILD_STUDIO=OFF || (pause & exit /b 1)
cmake --build build\tools --config Release --parallel || (pause & exit /b 1)
echo.
echo Built: build\tools\ps2xRecomp\Release\ps2_recomp.exe
pause
