@echo off
rem Step 3: translate SLUS_206.94 (MIPS R5900) into C++ under recomp\output\
setlocal
cd /d "%~dp0"
set "RECOMP=build\tools\ps2xRecomp\Release\ps2_recomp.exe"
if not exist "%RECOMP%" (echo Run 2_build_tools.bat first. & pause & exit /b 1)
set "TOML=config\onimusha3.toml"
if exist "%TOML%" goto havetoml
echo config\onimusha3.toml not found - run 1_ghidra_analyze.bat for best results.
echo Falling back to the heuristic config. Expect many more unhandled-instruction errors.
set "TOML=config\onimusha3_analyzer_fallback.toml"
:havetoml
rem Start from an empty output folder so files from an earlier run can't mix with this one
if exist output rmdir /s /q output
echo Recompiling with %TOML% ...
"%RECOMP%" "%TOML%" > recompile.log 2>&1
set "RC=%ERRORLEVEL%"
for /f %%N in ('findstr /c:"[error]" recompile.log ^| find /c /v ""') do set "NERR=%%N"
echo.
if not "%RC%"=="0" (echo FAILED with exit code %RC%. See recompile.log & pause & exit /b %RC%)
echo Recompilation succeeded. Log: recompile.log
echo %NERR% unhandled-instruction warnings (expected: about 7,600 with the Ghidra config;
echo most are data areas, see README). Next: 4_build_runtime.bat
pause
