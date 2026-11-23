# Runs Ghidra's headless analyzer without going through analyzeHeadless.bat / launch.bat.
# Those batch files break on paths and environment values that cmd.exe cannot parse inside
# ( ) blocks (for example the "(USA)" in this folder's name), so this builds the same Java
# command line that launch.bat would and starts java.exe directly.
#
# Usage: ghidra_headless.ps1 <ghidraDir> <javaHome> <maxMem> <AnalyzeHeadless arguments...>
# Exit code: Ghidra's.

if ($args.Count -lt 4) {
    Write-Host "Usage: ghidra_headless.ps1 <ghidraDir> <javaHome> <maxMem> <analyzeHeadless arguments...>"
    exit 2
}
$ghidraDir = [System.IO.Path]::GetFullPath([string]$args[0])
$javaHome  = [System.IO.Path]::GetFullPath([string]$args[1])
$maxMem    = [string]$args[2]
$rest      = @($args[3..($args.Count - 1)] | ForEach-Object { [string]$_ })

$isWin = ($env:OS -eq 'Windows_NT')
$java = Join-Path $javaHome (Join-Path 'bin' ($(if ($isWin) { 'java.exe' } else { 'java' })))
if (-not (Test-Path $java)) { Write-Host "ERROR: java not found at $java"; exit 1 }
$support = Join-Path $ghidraDir 'support'
$launchSupport = Join-Path $support 'LaunchSupport.jar'
$utilityJar = Join-Path $ghidraDir (Join-Path 'Ghidra' (Join-Path 'Framework' (Join-Path 'Utility' (Join-Path 'lib' 'Utility.jar'))))
if (-not (Test-Path $launchSupport) -or -not (Test-Path $utilityJar)) {
    Write-Host "ERROR: Ghidra not found at $ghidraDir"
    exit 1
}

# VM arguments from support\launch.properties for this OS (same as launch.bat).
$vmArgs = @(& $java -cp $launchSupport LaunchSupport $ghidraDir -vmargs) | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() }
if ($LASTEXITCODE -ne 0 -or $vmArgs.Count -eq 0) {
    Write-Host "ERROR: could not read Ghidra's launch properties (LaunchSupport exit $LASTEXITCODE)"
    exit 1
}

$javaArgs = @()
if ($isWin -and $env:USERPROFILE) { $javaArgs += "-Duser.home=$($env:USERPROFILE)" }
$javaArgs += $vmArgs
$javaArgs += "-Xmx$maxMem"
$javaArgs += '-XX:ParallelGCThreads=2'
$javaArgs += '-XX:CICompilerCount=2'
$javaArgs += @('-cp', $utilityJar, 'ghidra.Ghidra', 'ghidra.app.util.headless.AnalyzeHeadless')
$javaArgs += $rest

& $java @javaArgs
exit $LASTEXITCODE
