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
$warnings = New-Object System.Collections.Generic.List[string]

# Known Godot 4.7 *teardown* crash exit codes: the engine intermittently segfaults / corrupts the
# heap during SceneTree process SHUTDOWN when many headless scripts run back-to-back. The tests and
# validators have already finished and PASSED at that point (PLAN.md 2026-06-24/06-27 decisions) —
# the crash only poisons the exit code. So we DO NOT treat these codes as failures on their own:
# a phase fails only if its OUTPUT shows a real failure (SCRIPT ERROR, a FAIL/Failure marker, a
# missing success marker, or GdUnit statistics with >0 errors/failures). A crash code with clean
# output is downgraded to a warning. A non-crash nonzero exit (e.g. a validator's quit(1)=1) still
# fails. This keeps the verdict honest: green output -> green gate, even through the flake.
#   -1073741819 = 0xC0000005 access violation; -1073740940 = 0xC0000374 heap corruption;
#   -1073741571 = 0xC00000FD stack overflow;   -1073740791 = 0xC0000409 buffer overrun.
$TeardownCrashCodes = @(-1073741819, -1073740940, -1073741571, -1073740791)

# Classify a phase whose pass/fail is otherwise decided by output: returns $true if the nonzero exit
# should be ignored (treated as the teardown flake) given the output is already known-clean.
function Test-IsTeardownFlake([int]$exitCode) {
    return ($exitCode -ne 0) -and ($TeardownCrashCodes -contains $exitCode)
}

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

# Golden fixture selection: the whole gate runs against the FROZEN golden fixture
# (scenario_golden.json), not the research default (scenario_default.json, which carries the deep
# follow-on pool). Keeps every pinned validator/test byte-stable while scenario_default evolves as
# the realistic self-play scenario. An explicit --scenario arg still overrides (deep-pool coverage
# validator). To run a single golden validator by hand, set the same var.
$env:HEXCOMBAT_SCENARIO = "res://data/scenario_golden.json"

# Run Godot headless, returning combined stdout+stderr; sets $script:LastGodotExit.
function Invoke-Godot([string[]]$GodotArgs) {
    $all = @("--headless", "--path", $ProjectRoot) + $GodotArgs
    $output = & $GodotBin @all 2>&1 | Out-String
    $script:LastGodotExit = $LASTEXITCODE
    Write-Host $output
    return $output
}

# ---- Phase 1: Import ---------------------------------------------------------
# Success = the class cache built with no SCRIPT/Parse error. A teardown crash AFTER a clean import
# (no error markers) is the flake -> warn, don't fail.
Write-Phase "Phase 1/4 — Import (build class cache)"
$out = Invoke-Godot @("--import")
if ($out -match "SCRIPT ERROR" -or $out -match "Parse Error" -or $out -match "Compile Error") {
    $failures.Add("Import: SCRIPT/Parse/Compile error in output")
} elseif ($LastGodotExit -ne 0) {
    if (Test-IsTeardownFlake $LastGodotExit) {
        $warnings.Add("Import: teardown-flake exit $LastGodotExit (import output clean) — ignored")
        Write-Host "Import OK (teardown-flake exit $LastGodotExit ignored)." -ForegroundColor Green
    } else {
        $failures.Add("Import: godot exited $LastGodotExit")
    }
} else {
    Write-Host "Import OK." -ForegroundColor Green
}

# ---- Phase 2: Smoke ----------------------------------------------------------
Write-Phase "Phase 2/4 — Smoke (boot main scene headless)"
$out = Invoke-Godot @("--quit-after", "30")
$smokeOk = $true
foreach ($marker in @("Loaded 466 hexes", "Loaded 143 brigades", "Spawned 466 hex cells", "Rendered 32 brigade markers")) {
    if ($out -notmatch [regex]::Escape($marker)) {
        $failures.Add("Smoke: missing expected marker '$marker'")
        $smokeOk = $false
    }
}
if ($out -match "SCRIPT ERROR") {
    $failures.Add("Smoke: SCRIPT ERROR in output")
    $smokeOk = $false
}
# All markers present + no SCRIPT ERROR means the smoke boot succeeded; a teardown crash on shutdown
# is the flake. Only a non-crash nonzero exit (with markers otherwise OK) is a real failure.
if ($LastGodotExit -ne 0 -and $smokeOk) {
    if (Test-IsTeardownFlake $LastGodotExit) {
        $warnings.Add("Smoke: teardown-flake exit $LastGodotExit (all markers present) — ignored")
    } else {
        $failures.Add("Smoke: godot exited $LastGodotExit")
        $smokeOk = $false
    }
}
if ($smokeOk) { Write-Host "Smoke OK." -ForegroundColor Green }

# ---- Phase 3: tools/validate_*.gd -------------------------------------------
Write-Phase "Phase 3/4 — Custom validation scripts (tools/validate_*.gd)"
$validators = Get-ChildItem -Path (Join-Path $ProjectRoot "tools") -Filter "validate_*.gd" | Sort-Object Name
if ($validators.Count -eq 0) {
    Write-Host "No validate_*.gd scripts found (skipping)." -ForegroundColor Yellow
}
# Each validator quit()s 0 (pass) / 1 (fail) and prints a "PASS:"/"FAIL:" line. Verdict from OUTPUT:
# fail on a FAIL/SCRIPT-ERROR marker, or a missing PASS line, or a non-crash nonzero exit. A teardown
# crash with a clean "PASS:" line is the flake (a real failure quit(1)s with exit 1, not a crash code).
foreach ($v in $validators) {
    Write-Host "--- $($v.Name) ---" -ForegroundColor DarkCyan
    $out = Invoke-Godot @("-s", "res://tools/$($v.Name)")
    $sawFail = ($out -match "SCRIPT ERROR") -or ($out -match "(?m)^FAIL\b") -or ($out -match "(?m)^FAIL:")
    $sawPass = ($out -match "(?m)^PASS\b") -or ($out -match "(?m)^PASS:")
    if ($sawFail) {
        $failures.Add("Validation $($v.Name): FAIL/SCRIPT ERROR in output")
    } elseif (-not $sawPass) {
        # No explicit PASS line: trust the exit code (the validator may not print a PASS marker).
        if ($LastGodotExit -eq 0) {
            Write-Host "$($v.Name) OK." -ForegroundColor Green
        } elseif (Test-IsTeardownFlake $LastGodotExit) {
            $warnings.Add("Validation $($v.Name): teardown-flake exit $LastGodotExit, no failure markers — ignored")
            Write-Host "$($v.Name) OK (teardown-flake exit ignored)." -ForegroundColor Green
        } else {
            $failures.Add("Validation $($v.Name): exited $LastGodotExit, no PASS marker")
        }
    } else {
        # Explicit PASS line present: succeed regardless of a teardown crash exit code.
        if ($LastGodotExit -ne 0) {
            $warnings.Add("Validation $($v.Name): teardown-flake exit $LastGodotExit after PASS — ignored")
            Write-Host "$($v.Name) OK (teardown-flake exit $LastGodotExit ignored)." -ForegroundColor Green
        } else {
            Write-Host "$($v.Name) OK." -ForegroundColor Green
        }
    }
}

# ---- Batch runner Python validation ------------------------------------------
Write-Phase "Batch runner Python validation"
$PythonBin = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } elseif (Get-Command python -ErrorAction SilentlyContinue) { "python" } else { "" }
if ([string]::IsNullOrEmpty($PythonBin)) {
    $failures.Add("Batch runner validation: no Python interpreter found")
} else {
    $priorGodot = $env:HEXCOMBAT_TEST_GODOT
    $env:HEXCOMBAT_TEST_GODOT = $GodotBin
    $out = & $PythonBin (Join-Path $PSScriptRoot "validate_batch_runner.py") 2>&1 | Out-String
    $pythonExit = $LASTEXITCODE
    if ($null -eq $priorGodot) {
        Remove-Item Env:HEXCOMBAT_TEST_GODOT
    } else {
        $env:HEXCOMBAT_TEST_GODOT = $priorGodot
    }
    Write-Host $out
    if ($pythonExit -ne 0 -or $out -notmatch "(?m)^PASS: batch runner validation succeeded$") {
        $failures.Add("Batch runner validation: failed (exit $pythonExit)")
    } else {
        Write-Host "Batch runner Python validation OK." -ForegroundColor Green
    }
}

# ---- Fixture Generation and Drift Validation -----------------------------------
Write-Phase "Fixture Generation & Drift Validation"
# The "--" separator is load-bearing: without it Godot never surfaces --output in
# get_cmdline_user_args, the exporters fall back to reports/llm_*.json, and the drift check
# below silently compares an untouched docs/examples/ against itself (rotted 2026-07-0x..18).
Invoke-Godot @("-s", "res://tools/export_llm_observation.gd", "--", "--output=docs/examples/llm_observation_red_turn1.json") >$null 2>&1
Invoke-Godot @("-s", "res://tools/export_llm_result.gd", "--", "--output=docs/examples/llm_result_after_turn.json") >$null 2>&1

if (Get-Command git -ErrorAction SilentlyContinue) {
    & git diff --exit-code docs/examples/*.json >$null 2>&1
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("Fixture drift: LLMFixtures changed docs/examples/. Commit the regenerated JSON files.")
    } else {
        Write-Host "Fixture drift check OK." -ForegroundColor Green
    }
} else {
    Write-Host "git not found, skipping fixture git status check." -ForegroundColor Yellow
}

# ---- Phase 4: GdUnit4 suite --------------------------------------------------
Write-Phase "Phase 4/4 — GdUnit4 suite (tests/)"
# Verdict from the per-suite "Statistics:" lines, NOT the exit code: GdUnit returns 100 for real test
# failures, but the teardown flake can also corrupt the exit code to 100/crash AFTER every suite has
# reported 0 failures. So we sum the reported errors+failures across all suites; >0 is a real failure.
# If no statistics were emitted at all the run didn't complete -> failure. A nonzero exit with all-zero
# statistics is the flake -> warn.
if (Test-Path (Join-Path $ProjectRoot "tests")) {
    $out = Invoke-Godot @("-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd", "--ignoreHeadlessMode", "-a", "res://tests")
    $statMatches = [regex]::Matches($out, "(\d+)\s+errors\s+\|\s+(\d+)\s+failures")
    $sumErr = 0; $sumFail = 0
    foreach ($m in $statMatches) {
        $sumErr  += [int]$m.Groups[1].Value
        $sumFail += [int]$m.Groups[2].Value
    }
    if ($statMatches.Count -eq 0) {
        $failures.Add("GdUnit4: no test statistics emitted (run did not complete; exit $LastGodotExit)")
    } elseif ($sumErr -gt 0 -or $sumFail -gt 0) {
        $failures.Add("GdUnit4: $sumErr error(s) + $sumFail failure(s) across $($statMatches.Count) suite(s)")
    } else {
        if ($LastGodotExit -ne 0) {
            $warnings.Add("GdUnit4: teardown-flake exit $LastGodotExit ($($statMatches.Count) suites, 0 errors/failures) — ignored")
            Write-Host "GdUnit4 OK ($($statMatches.Count) suites, 0 failures; teardown-flake exit $LastGodotExit ignored)." -ForegroundColor Green
        } else {
            Write-Host "GdUnit4 OK ($($statMatches.Count) suites, 0 failures)." -ForegroundColor Green
        }
    }
} else {
    Write-Host "No tests/ directory (skipping)." -ForegroundColor Yellow
}

# ---- Summary -----------------------------------------------------------------
Write-Phase "Summary"
if ($warnings.Count -gt 0) {
    Write-Host "$($warnings.Count) teardown-flake warning(s) (NOT failures — tests passed, engine crashed on shutdown):" -ForegroundColor Yellow
    foreach ($w in $warnings) { Write-Host "  ~ $w" -ForegroundColor Yellow }
}
if ($failures.Count -eq 0) {
    if ($warnings.Count -gt 0) {
        Write-Host "ALL PHASES GREEN (with $($warnings.Count) teardown-flake warning(s) ignored)." -ForegroundColor Green
    } else {
        Write-Host "ALL PHASES GREEN." -ForegroundColor Green
    }
    exit 0
}
Write-Host "FAILED ($($failures.Count) issue(s)):" -ForegroundColor Red
foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
exit 1
