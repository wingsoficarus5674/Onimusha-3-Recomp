@echo off
rem Step 3: translate SLUS_206.94 (MIPS R5900) into C++ under recomp\output\
setlocal
cd /d "%~dp0"
set "RECOMP=build\tools\ps2xRecomp\Release\ps2_recomp.exe"
if not exist "%RECOMP%" (echo Run 2_build_tools.bat first. & pause & exit /b 1)
set "TOML=config\onimusha3.toml"
if not exist "%TOML%" (
  echo config\onimusha3.toml not found - run 1_ghidra_analyze.bat for best results.
  echo Falling back to the heuristic config. Expect many unhandled-instruction errors.
  set "TOML=config\onimusha3_analyzer_fallback.toml"
)
"%RECOMP%" "%TOML%" > recompile.log 2>&1
echo Exit code %ERRORLEVEL%. Log: recompile.log
findstr /c:"[error]" recompile.log | find /c /v "" 
echo ^^ number of error lines
pause
