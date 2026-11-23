@echo off
rem Step 5: boot the recompiled game. The disc root (cdrom0:) is the game\ folder next to the ELF.
rem Everything the runtime prints is also saved to run_log.txt (attach it when reporting a problem).
setlocal
cd /d "%~dp0"
if "%~1"=="__run" goto run
powershell -NoProfile -Command "cmd /c 'call %~nx0 __run 2>&1' | Tee-Object -FilePath 'run_log.txt'"
pause
exit /b

:run
for /r build\runtime %%F in (ps2EntryRunner.exe) do if exist "%%F" set "EXE=%%F"
if not defined EXE (echo Run 4_build_runtime.bat first. & exit /b 1)
"%EXE%" "%CD%\game\SLUS_206.94"
echo.
echo ps2EntryRunner exited with code %ERRORLEVEL%
exit /b 0
