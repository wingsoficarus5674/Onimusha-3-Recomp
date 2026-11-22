@echo off
rem Step 4: copy generated C++ into the runtime and build ps2EntryRunner.exe (the native PC executable).
setlocal
cd /d "%~dp0"
if not exist output\register_functions.cpp (echo Run 3_recompile.bat first. & pause & exit /b 1)
set "RT=tools\PS2Recomp\ps2xRuntime"
copy /y output\*.cpp "%RT%\src\runner\" >nul
copy /y output\*.h   "%RT%\include\" >nul
cmake -S tools\PS2Recomp -B build\runtime -DPS2X_BUILD_RECOMP=OFF -DPS2X_BUILD_ANALYZER=OFF -DPS2X_BUILD_TEST=OFF -DPS2X_BUILD_STUDIO=OFF || (pause & exit /b 1)
cmake --build build\runtime --config Release --parallel --target ps2EntryRunner || (pause & exit /b 1)
echo.
echo Built. Run with:  5_run.bat
pause
