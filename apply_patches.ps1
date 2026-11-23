# Applies patches\*.patch to tools\PS2Recomp in order, each exactly once.
#
# Applied patches are listed in tools\PS2Recomp\.onimusha3-applied-patches.txt. A tree without that
# list (patched by an older version of these scripts) is detected once: patches are always applied
# in order, so the newest patch that can be reversed cleanly is the last one applied, and every patch
# before it is applied too. (Checking each patch on its own doesn't work: a later patch that edits
# the same lines makes an applied patch look unapplied.)
#
# --ignore-whitespace: files in tools\PS2Recomp may have CRLF line endings (Windows checkout).
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File apply_patches.ps1
# Exit code 0 on success, 1 if a patch can't be applied.

$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath $PSScriptRoot

$tree = 'tools/PS2Recomp'
$stamp = Join-Path $PSScriptRoot 'tools\PS2Recomp\.onimusha3-applied-patches.txt'
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'tools\PS2Recomp'))) {
    Write-Host "tools\PS2Recomp not found - run 0_setup.ps1 first."
    exit 1
}
$patches = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'patches') -Filter '*.patch' | Sort-Object Name)

function Test-GitApply([string[]]$extra, [string]$patchPath) {
    $gitArgs = @('apply', '--ignore-whitespace') + $extra + @("--directory=$tree", $patchPath)
    & git @gitArgs 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

$applied = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $stamp) {
    foreach ($line in Get-Content -LiteralPath $stamp) {
        $name = $line.Trim()
        if ($name) { $applied.Add($name) }
    }
} else {
    # One-time detection for trees patched before the list existed.
    $last = -1
    for ($i = $patches.Count - 1; $i -ge 0; $i--) {
        if (Test-GitApply @('--reverse', '--check') $patches[$i].FullName) { $last = $i; break }
    }
    for ($i = 0; $i -le $last; $i++) { $applied.Add($patches[$i].Name) }
    if ($last -ge 0) {
        Write-Host "Found patches up to $($patches[$last].Name) already applied."
    }
    Set-Content -LiteralPath $stamp -Value $applied -Encoding ASCII
}

foreach ($p in $patches) {
    if ($applied.Contains($p.Name)) { continue }
    if (-not (Test-GitApply @('--check') $p.FullName)) {
        Write-Host "Failed to apply $($p.Name):"
        & git apply --ignore-whitespace --check "--directory=$tree" $p.FullName
        Write-Host "tools\PS2Recomp has local changes this patch conflicts with. To start clean, delete"
        Write-Host "tools\PS2Recomp, run 0_setup.ps1 again, then 2_build_tools.bat."
        exit 1
    }
    & git apply --ignore-whitespace "--directory=$tree" $p.FullName
    if ($LASTEXITCODE -ne 0) { Write-Host "Failed to apply $($p.Name)"; exit 1 }
    $applied.Add($p.Name)
    Add-Content -LiteralPath $stamp -Value $p.Name -Encoding ASCII
    Write-Host "Applied $($p.Name)"
}
exit 0
