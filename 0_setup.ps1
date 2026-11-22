# Step 0: download the tools into tools\ and extract the game files from your own ISO into game\.
# Usage (PowerShell):  .\0_setup.ps1 -Iso "C:\path\to\Onimusha 3 - Demon Siege (USA).iso"
param([Parameter(Mandatory=$true)][string]$Iso)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force downloads, tools, game | Out-Null

$files = @(
  @{ url='https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.2_build/ghidra_12.2_PUBLIC_20261016.zip';
     sha='2c2cd776db3c1f6a097ba418922378ac3649cadd5e844a6f5f088ae628a7be67' },
  @{ url='https://github.com/chaoticgd/ghidra-emotionengine-reloaded/releases/download/v2.1.39/ghidra_12.2_PUBLIC_20261029_ghidra-emotionengine-reloaded.zip'; sha=$null },
  @{ url='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jdk_x64_windows_hotspot_21.0.13_9.zip';
     sha='a4dbaa05fca4bd89d84584e58c459bd732efebb1722af80ab13c6516832004f9' },
  @{ url='https://codeload.github.com/ran-j/PS2Recomp/zip/refs/heads/main'; name='PS2Recomp-main.zip'; sha=$null }
)
foreach ($f in $files) {
  $name = if ($f.name) { $f.name } else { [uri]::UnescapeDataString(($f.url -split '/')[-1]) }
  $out = Join-Path downloads $name
  if (-not (Test-Path $out)) { Write-Host "Downloading $name"; Invoke-WebRequest $f.url -OutFile $out }
  if ($f.sha -and (Get-FileHash $out -Algorithm SHA256).Hash -ne $f.sha.ToUpper()) { throw "Checksum mismatch: $name" }
}
if (-not (Test-Path tools\ghidra_12.2_PUBLIC)) { Expand-Archive downloads\ghidra_12.2_PUBLIC_20261016.zip tools }
if (-not (Test-Path tools\ghidra_12.2_PUBLIC\Ghidra\Extensions\ghidra-emotionengine-reloaded)) {
  Expand-Archive downloads\ghidra_12.2_PUBLIC_20261029_ghidra-emotionengine-reloaded.zip tools\ghidra_12.2_PUBLIC\Ghidra\Extensions }
if (-not (Test-Path 'tools\jdk-21.0.13+9')) { Expand-Archive downloads\OpenJDK21U-jdk_x64_windows_hotspot_21.0.13_9.zip tools }
if (-not (Test-Path tools\PS2Recomp)) { Expand-Archive downloads\PS2Recomp-main.zip tools; Rename-Item tools\PS2Recomp-main PS2Recomp }

# Copy disc contents (mount the ISO with Windows' built-in support)
$img = Mount-DiskImage -ImagePath (Resolve-Path $Iso) -PassThru
try {
  $drive = ($img | Get-Volume).DriveLetter + ':\'
  Write-Host "Copying disc contents from $drive (2.2 GB)"
  Copy-Item "$drive*" game -Recurse -Force
  Get-ChildItem game -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }
} finally { Dismount-DiskImage -ImagePath (Resolve-Path $Iso) | Out-Null }

$h = (Get-FileHash game\SLUS_206.94 -Algorithm SHA256).Hash
if ($h -ne '22955889D3DB316FB039D0C805DEBC8188C384211FB4DDBFEDC3E1238E7DD78A') { Write-Warning "SLUS_206.94 hash differs - not the USA v1.01 disc this config targets" }
Write-Host 'Setup complete. Next: 1_ghidra_analyze.bat'
