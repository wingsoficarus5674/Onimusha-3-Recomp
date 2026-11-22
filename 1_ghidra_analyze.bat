@echo off
rem Step 1: Ghidra auto-analysis of SLUS_206.94 + export of the function map for PS2Recomp.
rem Uses the bundled JDK 25 (Ghidra 12.2 requires Java 25+) and the Emotion Engine (R5900) extension.
rem Output: config\onimusha3.toml + config\onimusha3_functions.csv
rem Everything printed is also saved to config\1_ghidra_analyze_output.txt
setlocal
cd /d "%~dp0"
if "%~1"=="__run" goto run
if not exist config mkdir config
powershell -NoProfile -Command "cmd /c 'call %~nx0 __run 2>&1' | Tee-Object -FilePath 'config\1_ghidra_analyze_output.txt'"
pause
exit /b

:run
rem Ghidra's launch.bat breaks on ")" in any argument, e.g. "...(USA)\...".
rem Work around it by mapping this folder to a free drive letter for the duration of the run.
set "REALROOT=%CD%"
set "DRV="
for %%L in (P Q R S T U V W X Y Z) do if not defined DRV if not exist %%L:\ set "DRV=%%L:"
if not defined DRV goto nodrive
subst %DRV% "%REALROOT%"
if errorlevel 1 goto nodrive
echo Mapped %DRV% to %REALROOT% for this run.
pushd %DRV%\
set "ROOT=%DRV%"
set "JAVA_HOME=%ROOT%\tools\jdk-25.0.5.1+2"
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "GHIDRA_HEADLESS_MAXMEM=4G"
set "RESULT=1"
if not exist "%JAVA_HOME%\bin\java.exe" goto nojava
if not exist "%ROOT%\tools\ghidra_12.2_PUBLIC\support\analyzeHeadless.bat" goto noghidra
if not exist "%ROOT%\game\SLUS_206.94" goto noelf
if not exist ghidra_project mkdir ghidra_project
echo Using Java:
java -version 2>&1
echo.
echo Starting Ghidra headless analysis (a few minutes)...
call "%ROOT%\tools\ghidra_12.2_PUBLIC\support\analyzeHeadless.bat" "%ROOT%\ghidra_project" Onimusha3 -import "%ROOT%\game\SLUS_206.94" -overwrite -processor r5900:LE:32:default -scriptPath "%ROOT%\tools\PS2Recomp\ps2xRecomp\tools\ghidra" -postScript ExportPS2Functions.java "%ROOT%\config\onimusha3.toml" "%ROOT%\config\onimusha3_functions.csv" -log "%ROOT%\config\ghidra_headless.log"
echo Ghidra exit code: %ERRORLEVEL%
if not exist config\onimusha3.toml goto failed
rem Make paths in the generated config relative to this folder (run steps from here)
powershell -NoProfile -Command "(Get-Content config\onimusha3.toml) -replace '^input = .*', 'input = ''game/SLUS_206.94''' -replace '^output = .*', 'output = ''output/''' -replace '^ghidra_output = .*', 'ghidra_output = ''config/onimusha3_functions.csv''' | Set-Content config\onimusha3.toml"
echo.
echo Done. Wrote config\onimusha3.toml and config\onimusha3_functions.csv
echo The analysed project is in ghidra_project\ (open with tools\ghidra_12.2_PUBLIC\ghidraRun.bat).
set "RESULT=0"
goto cleanup

:nojava
echo ERROR: Java 25 not found in tools\jdk-25.0.5.1+2 - run 0_setup.ps1 first.
goto cleanup
:noghidra
echo ERROR: Ghidra not found in tools\ghidra_12.2_PUBLIC - run 0_setup.ps1 first.
goto cleanup
:noelf
echo ERROR: game\SLUS_206.94 not found - run 0_setup.ps1 with your ISO first.
goto cleanup
:failed
echo.
echo Ghidra export failed. See config\1_ghidra_analyze_output.txt and config\ghidra_headless.log
goto cleanup
:nodrive
echo ERROR: could not map a free drive letter (P: to Z:) with subst.
echo Alternatively, move this folder to a path without ( ) characters and run again.
exit /b 1

:cleanup
popd
subst %DRV% /d
exit /b %RESULT%
