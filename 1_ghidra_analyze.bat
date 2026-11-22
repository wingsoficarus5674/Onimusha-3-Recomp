@echo off
rem Step 1: Ghidra auto-analysis of SLUS_206.94 + export of function map for PS2Recomp.
rem Uses the bundled JDK 21 and Ghidra 12.2 with the Emotion Engine (R5900) extension.
rem Expect 15-60 minutes depending on your CPU. Output: config\onimusha3.toml + config\onimusha3_functions.csv
setlocal
cd /d "%~dp0"
set "ROOT=%CD%"
set "JAVA_HOME=%ROOT%\tools\jdk-21.0.13+9"
set "PATH=%JAVA_HOME%\bin;%PATH%"
if not exist "%ROOT%\config" mkdir "%ROOT%\config"
if not exist "%ROOT%\ghidra_project" mkdir "%ROOT%\ghidra_project"

call "%ROOT%\tools\ghidra_12.2_PUBLIC\support\analyzeHeadless.bat" "%ROOT%\ghidra_project" Onimusha3 ^
  -import "%ROOT%\game\SLUS_206.94" -overwrite ^
  -processor r5900:LE:32:default ^
  -scriptPath "%ROOT%\tools\PS2Recomp\ps2xRecomp\tools\ghidra" ^
  -postScript ExportPS2Functions.java "%ROOT%\config\onimusha3.toml" "%ROOT%\config\onimusha3_functions.csv" ^
  -log "%ROOT%\config\ghidra_headless.log"

if not exist "%ROOT%\config\onimusha3.toml" (
  echo.
  echo Ghidra export failed - see config\ghidra_headless.log
  pause
  exit /b 1
)
rem Point generated C++ at recomp\output instead of config\output
powershell -NoProfile -Command "(Get-Content '%ROOT%\config\onimusha3.toml') -replace '^output = .*','output = \"output/\"' | Set-Content '%ROOT%\config\onimusha3.toml'"
echo.
echo Done. Function map written to config\onimusha3.toml and config\onimusha3_functions.csv
echo The analysed project is in ghidra_project\ - open it in Ghidra (tools\ghidra_12.2_PUBLIC\ghidraRun.bat) to refine functions.
pause
