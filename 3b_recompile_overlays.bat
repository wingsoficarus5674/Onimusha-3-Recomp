@echo off
rem Step 3b: recompile the game's code overlays (title screen, menus, areas, enemies).
rem Onimusha 3 keeps most of its code in compressed modules inside game\IMAGE\IMAGE.AFS that it loads
rem into RAM at 0x00D00000 at run time. This step:
rem   1. extracts every code module to build\overlays\elf (overlays.ps1 -Extract)
rem   2. runs Ghidra on them to find their functions (a few minutes)
rem   3. recompiles each module with ps2_recomp, plus the main-ELF code that only overlays call
rem      (entry points 3_recompile.bat had no reason to create; needs output\ from step 3)
rem   4. writes the C++ to output_overlays\ (overlays.ps1 -Generate); 4_build_runtime.bat builds it in.
rem Everything printed is also saved to build\3b_recompile_overlays_output.txt
setlocal
cd /d "%~dp0"
if "%~1"=="__run" goto run
if not exist build mkdir build
powershell -NoProfile -Command "cmd /c 'call %~nx0 __run 2>&1' | Tee-Object -FilePath 'build\3b_recompile_overlays_output.txt'"
pause
exit /b

:run
set "RECOMP=build\tools\ps2xRecomp\Release\ps2_recomp.exe"
if not exist "%RECOMP%" (echo Run 2_build_tools.bat first. & exit /b 1)
if not exist "game\IMAGE\IMAGE.AFS" (echo game\IMAGE\IMAGE.AFS not found - run 0_setup.ps1 with your ISO first. & exit /b 1)
if not exist "output\register_functions.cpp" (echo Run 3_recompile.bat first. & exit /b 1)
set "WORK=build\overlays"
if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%WORK%\csv" "%WORK%\recomp" "%WORK%\ghidra_scripts" "%WORK%\ghidra_project"

echo [1/4] Extracting code modules from IMAGE.AFS...
powershell -NoProfile -ExecutionPolicy Bypass -File overlays.ps1 -Extract game\IMAGE\IMAGE.AFS "%WORK%"
if errorlevel 1 (echo Extraction FAILED. & exit /b 1)
copy /y ghidra_scripts\SeedOverlayFunctions.java "%WORK%\ghidra_scripts\" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File overlays.ps1 -GhidraScript tools\PS2Recomp\ps2xRecomp\tools\ghidra\ExportPS2Functions.java "%WORK%\ghidra_scripts\ExportPS2Overlay.java"
if errorlevel 1 (echo Could not prepare the Ghidra export script. & exit /b 1)

echo [2/4] Ghidra analysis of the modules...
rem Ghidra's launch.bat breaks on ")" in any argument, so map this folder to a free drive letter.
set "REALROOT=%CD%"
set "DRV="
for %%L in (P Q R S T U V W X Y Z) do if not defined DRV if not exist %%L:\ set "DRV=%%L:"
if not defined DRV (echo ERROR: could not map a free drive letter P: to Z: with subst. & exit /b 1)
subst %DRV% "%REALROOT%"
if errorlevel 1 (echo ERROR: subst failed. & exit /b 1)
pushd %DRV%\
set "JAVA_HOME=%DRV%\tools\jdk-25.0.5.1+2"
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "GHIDRA_HEADLESS_MAXMEM=4G"
call "%DRV%\tools\ghidra_12.2_PUBLIC\support\analyzeHeadless.bat" "%DRV%\%WORK%\ghidra_project" overlays -import "%DRV%\%WORK%\elf" -recursive -deleteProject -processor r5900:LE:32:default -scriptPath "%DRV%\%WORK%\ghidra_scripts" -preScript SeedOverlayFunctions.java "%DRV%\%WORK%\seeds" -postScript ExportPS2Overlay.java "%DRV%\%WORK%\csv" -log "%DRV%\%WORK%\ghidra_headless.log"
popd
subst %DRV% /d
set "NCSV=0"
for %%F in ("%WORK%\csv\*.csv") do set /a NCSV+=1
set "NELF=0"
for %%F in ("%WORK%\elf\*.elf") do set /a NELF+=1
echo Ghidra exported %NCSV% of %NELF% modules.
if not "%NCSV%"=="%NELF%" (echo Ghidra analysis FAILED - see %WORK%\ghidra_headless.log & exit /b 1)

echo [3/4] Recompiling the modules...
set "NFAIL=0"
for %%F in ("%WORK%\elf\*.elf") do call :recompile "%%~nF"
if not "%NFAIL%"=="0" (echo %NFAIL% module^(s^) failed to recompile - see %WORK%\recomp\*.log & exit /b 1)
powershell -NoProfile -ExecutionPolicy Bypass -File overlays.ps1 -MainExtra output\register_functions.cpp config\onimusha3_functions.csv game\SLUS_206.94 "%WORK%\elf" "%WORK%\main_extra.csv"
if errorlevel 1 (echo Finding main-ELF entry points FAILED. & exit /b 1)
mkdir "%WORK%\recomp\main_extra" 2>nul
> "%WORK%\recomp\main_extra.toml" (
  echo [general]
  echo input = "game/SLUS_206.94"
  echo output = "%WORK:\=/%/recomp/main_extra/"
  echo ghidra_output = "%WORK:\=/%/main_extra.csv"
  echo single_file_output = false
  echo patch_syscalls = false
  echo patch_cop0 = true
  echo patch_cache = true
  echo stubs = []
  echo untracked_stubs = []
  echo skip = []
)
"%RECOMP%" "%WORK%\recomp\main_extra.toml" > "%WORK%\recomp\main_extra.log" 2>&1
if errorlevel 1 (echo Recompiling main-ELF entry points FAILED - see %WORK%\recomp\main_extra.log & exit /b 1)

echo [4/4] Writing C++ to output_overlays\ ...
powershell -NoProfile -ExecutionPolicy Bypass -File overlays.ps1 -Generate "%WORK%\recomp" "%WORK%\elf" output_overlays game\SLUS_206.94
if errorlevel 1 (echo Generating overlay sources FAILED. & exit /b 1)
echo.
echo Done. Next: 4_build_runtime.bat
exit /b 0

:recompile
set "N=%~1"
mkdir "%WORK%\recomp\%N%" 2>nul
> "%WORK%\recomp\%N%.toml" (
  echo [general]
  echo input = "%WORK:\=/%/elf/%N%.elf"
  echo output = "%WORK:\=/%/recomp/%N%/"
  echo ghidra_output = "%WORK:\=/%/csv/%N%.csv"
  echo single_file_output = false
  echo patch_syscalls = false
  echo patch_cop0 = true
  echo patch_cache = true
  echo stubs = []
  echo untracked_stubs = []
  echo skip = []
)
"%RECOMP%" "%WORK%\recomp\%N%.toml" > "%WORK%\recomp\%N%.log" 2>&1
if errorlevel 1 (echo   %N%: FAILED & set /a NFAIL+=1)
exit /b 0
