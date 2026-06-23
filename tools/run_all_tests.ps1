<#
.SYNOPSIS
    Canonical verification gate for HexCombat.

.DESCRIPTION
    Runs, in order, exiting non-zero on the first failing phase:
      1. Import        — build the class cache (godot --import).
      2. Smoke         — boot the main scene headless; assert data loaded, no script errors.
      3. Validation    — every tools/validate_*.gd custom headless check (each quit()s 0/1).
      4. GdUnit4       — the structured test suite under tests/ (exit 0 pass, non-zero fail).

    Godot binary resolution: -GodotBin arg, else $env:GODOT_BIN, else the default below.

.EXAMPLE
    pwsh -File tools/run_all_tests.ps1
    pwsh -File tools/run_all_tests.ps1 -GodotBin "C:\Godot_v4.7-stable_win64.exe"
#>
[CmdletBinding()]
param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "C:\Godot_v4.7-stable_win64.exe" })
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path $GodotBin)) {
    Write-Host "FATAL: Godot binary not found at '$GodotBin'." -ForegroundColor Red
    Write-Host "Set -GodotBin or `$env:GODOT_BIN." -ForegroundColor Red
    exit 2
}

function Write-Phase([string]$name) {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host " $name" -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
}

# Run Godot headless, returning combined stdout+stderr; sets $script:LastGodotExit.
function Invoke-Godot([string[]]$GodotArgs) {
    $all = @("--headless", "--path", $ProjectRoot) + $GodotArgs
    $output = & $GodotBin @all 2>&1 | Out-String
    $script:LastGodotExit = $LASTEXITCODE
    Write-Host $output
    return $output
}

# ---- Phase 1: Import ---------------------------------------------------------
Write-Phase "Phase 1/4 — Import (build class cache)"
$out = Invoke-Godot @("--import")
if ($LastGodotExit -ne 0) {
    $failures.Add("Import: godot exited $LastGodotExit")
} elseif ($out -match "SCRIPT ERROR") {
    $failures.Add("Import: SCRIPT ERROR in output")
} else {
    Write-Host "Import OK." -ForegroundColor Green
}

# ---- Phase 2: Smoke ----------------------------------------------------------
Write-Phase "Phase 2/4 — Smoke (boot main scene headless)"
$out = Invoke-Godot @("--quit-after", "30")
$smokeOk = $true
foreach ($marker in @("Loaded 455 hexes", "Loaded 111 brigades", "Spawned 455 hex cells")) {
    if ($out -notmatch [regex]::Escape($marker)) {
        $failures.Add("Smoke: missing expected marker '$marker'")
        $smokeOk = $false
    }
}
if ($out -match "SCRIPT ERROR") {
    $failures.Add("Smoke: SCRIPT ERROR in output")
    $smokeOk = $false
}
if ($LastGodotExit -ne 0) {
    $failures.Add("Smoke: godot exited $LastGodotExit")
    $smokeOk = $false
}
if ($smokeOk) { Write-Host "Smoke OK." -ForegroundColor Green }

# ---- Phase 3: tools/validate_*.gd -------------------------------------------
Write-Phase "Phase 3/4 — Custom validation scripts (tools/validate_*.gd)"
$validators = Get-ChildItem -Path (Join-Path $ProjectRoot "tools") -Filter "validate_*.gd" | Sort-Object Name
if ($validators.Count -eq 0) {
    Write-Host "No validate_*.gd scripts found (skipping)." -ForegroundColor Yellow
}
foreach ($v in $validators) {
    Write-Host "--- $($v.Name) ---" -ForegroundColor DarkCyan
    $out = Invoke-Godot @("-s", "res://tools/$($v.Name)")
    if ($LastGodotExit -ne 0) {
        $failures.Add("Validation $($v.Name): exited $LastGodotExit")
    } elseif ($out -match "SCRIPT ERROR") {
        $failures.Add("Validation $($v.Name): SCRIPT ERROR in output")
    } else {
        Write-Host "$($v.Name) OK." -ForegroundColor Green
    }
}

# ---- Phase 4: GdUnit4 suite --------------------------------------------------
Write-Phase "Phase 4/4 — GdUnit4 suite (tests/)"
if (Test-Path (Join-Path $ProjectRoot "tests")) {
    $out = Invoke-Godot @("-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd", "--ignoreHeadlessMode", "-a", "res://tests")
    if ($LastGodotExit -ne 0) {
        $failures.Add("GdUnit4: exited $LastGodotExit (test failure or error)")
    } else {
        Write-Host "GdUnit4 OK." -ForegroundColor Green
    }
} else {
    Write-Host "No tests/ directory (skipping)." -ForegroundColor Yellow
}

# ---- Summary -----------------------------------------------------------------
Write-Phase "Summary"
if ($failures.Count -eq 0) {
    Write-Host "ALL PHASES GREEN." -ForegroundColor Green
    exit 0
}
Write-Host "FAILED ($($failures.Count) issue(s)):" -ForegroundColor Red
foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
exit 1
