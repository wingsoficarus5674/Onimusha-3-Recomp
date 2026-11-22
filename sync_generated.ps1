# Copy generated files from -Src to -Dst only when their contents differ, so unchanged
# files keep their timestamps and MSBuild doesn't recompile them.
# With -Prune, files in -Dst that match -Filter but are not in -Src are deleted (stale output).
param(
  [Parameter(Mandatory=$true)][string]$Src,
  [Parameter(Mandatory=$true)][string]$Dst,
  [string[]]$Filter = @('*.cpp'),
  [switch]$Prune
)
$ErrorActionPreference = 'Stop'
$copied = 0; $removed = 0; $same = 0
$srcNames = @{}
foreach ($pattern in $Filter) {
  foreach ($f in Get-ChildItem -LiteralPath $Src -Filter $pattern -File) {
    $srcNames[$f.Name] = $true
    $d = Join-Path $Dst $f.Name
    $needCopy = $true
    if (Test-Path -LiteralPath $d) {
      $di = Get-Item -LiteralPath $d
      if ($di.Length -eq $f.Length) {
        $a = [System.IO.File]::ReadAllBytes($f.FullName)
        $b = [System.IO.File]::ReadAllBytes($di.FullName)
        if ([System.Linq.Enumerable]::SequenceEqual($a, $b)) { $needCopy = $false }
      }
    }
    if ($needCopy) { Copy-Item -LiteralPath $f.FullName -Destination $d -Force; $copied++ } else { $same++ }
  }
  if ($Prune) {
    foreach ($g in Get-ChildItem -LiteralPath $Dst -Filter $pattern -File) {
      if (-not $srcNames.ContainsKey($g.Name)) { Remove-Item -LiteralPath $g.FullName -Force; $removed++ }
    }
  }
}
Write-Host ("{0}: {1} changed/new copied, {2} unchanged, {3} stale removed" -f ($Filter -join ','), $copied, $same, $removed)
