@echo off
rem Step 5: boot the recompiled game. The disc root (cdrom0:) is the game\ folder next to the ELF.
setlocal
cd /d "%~dp0"
for /r build\runtime %%F in (ps2EntryRunner.exe) do if exist "%%F" set "EXE=%%F"
if not defined EXE (echo Run 4_build_runtime.bat first. & pause & exit /b 1)
"%EXE%" "%CD%\game\SLUS_206.94"
pause
