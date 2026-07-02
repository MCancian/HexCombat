# Batch research runner (harness B2): N seeded headless self-play games, process-per-run,
# over a scenario x policy matrix with a COMMON seed set (common random numbers, so condition
# differences are attributable). Per-game JSON records checkpoint to the output directory —
# a record that already exists is skipped, so re-running the same command resumes a crashed
# batch and loses at most one game.
#
# VERDICT IS ARTIFACT-BASED, not exit-code-based: a game is OK iff its record file exists,
# parses, has all_resolved=true and no index_violations. (Godot 4.7's known teardown flake can
# corrupt exit codes AFTER a successful run — same policy as run_all_tests.ps1.) Each game's
# stdout/stderr land next to its record as .log/.err.log for archaeology.
#
#   pwsh -File tools/run_batch.ps1 -Name smoke -N 30
#   pwsh -File tools/run_batch.ps1 -Name mines_study -Scenarios default,more_mines -N 50 -Turns 40
#   pwsh -File tools/run_batch.ps1 -Name redo -Seeds 20260624,20260625 -Parallel 1
#
# Any single game re-runs deterministically (byte-identical record) via the command line stamped
# into each result row of manifest.json.
param(
    # Batch name -> output directory reports/batches/<Name> (git-ignored).
    [Parameter(Mandatory = $true)][string]$Name,
    [string[]]$Scenarios = @("default"),
    [string[]]$Policies = @("selfplay_default"),
    # Seed set: explicit -Seeds wins; otherwise BaseSeed..BaseSeed+N-1.
    [string[]]$Seeds = @(),
    [int]$N = 30,
    [int]$BaseSeed = 20260624,
    [int]$Turns = 30,
    [int]$Parallel = 4,
    [string]$Godot = "C:\Godot_v4.7-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
# `pwsh -File` passes "a,b" as ONE string — normalize comma-joined array params.
$Scenarios = @($Scenarios | ForEach-Object { $_ -split ',' })
$Policies = @($Policies | ForEach-Object { $_ -split ',' })
$Seeds = @($Seeds | ForEach-Object { "$_" -split ',' } | ForEach-Object { [int]$_ })
$repo = Split-Path -Parent $PSScriptRoot
if ($Seeds.Count -eq 0) { $Seeds = $BaseSeed..($BaseSeed + $N - 1) }

$outDir = Join-Path $repo "reports\batches\$Name"
$gamesDir = Join-Path $outDir "games"
New-Item -ItemType Directory -Force $gamesDir | Out-Null

# The full condition matrix; record filenames are the (condition, seed) identity.
$jobs = foreach ($scenario in $Scenarios) {
    foreach ($policy in $Policies) {
        foreach ($seed in $Seeds) {
            # Record filename uses the scenario's id (filename stem) — -Scenarios may carry full
            # variant file paths (e.g. from run_sweep.ps1), which are not valid in filenames.
            $scenarioId = [System.IO.Path]::GetFileNameWithoutExtension($scenario)
            $record = Join-Path $gamesDir ("{0}__{1}__seed{2}.json" -f $scenarioId, $policy, $seed)
            $gameArgs = @(
                "--headless", "--path", $repo,
                "-s", "res://tools/run_selfplay_game.gd", "--",
                "--scenario=$scenario", "--policy=$policy",
                "--seed=$seed", "--turns=$Turns", "--out=$record"
            )
            [pscustomobject]@{
                Scenario = $scenario; Policy = $policy; Seed = $seed
                Record   = $record
                Args     = $gameArgs
                Command  = "$Godot $($gameArgs -join ' ')"
            }
        }
    }
}

# A game is OK iff its record says so (see header). Returns $null for missing/unparseable.
function Read-GameVerdict([string]$recordPath) {
    if (-not (Test-Path $recordPath)) { return $null }
    try { $rec = Get-Content $recordPath -Raw | ConvertFrom-Json } catch { return $null }
    return [pscustomobject]@{
        Ok      = [bool]$rec.all_resolved -and (@($rec.index_violations).Count -eq 0)
        Summary = "scenario=$($rec.scenario_id) policy=$($rec.policy_id) seed=$($rec.base_seed) " +
                  "turns=$($rec.turns_played)/$($rec.turns_requested) game_over=$($rec.game_over) " +
                  "winner=$($rec.winner) census=$($rec.census.red):$($rec.census.green)"
    }
}

$pending = @($jobs | Where-Object { $null -eq (Read-GameVerdict $_.Record) })
Write-Host ("Batch '{0}': {1} games ({2} scenario(s) x {3} policy(ies) x {4} seed(s)); {5} already recorded, {6} to run." -f `
    $Name, $jobs.Count, $Scenarios.Count, $Policies.Count, $Seeds.Count, ($jobs.Count - $pending.Count), $pending.Count)

# Launch up to $Parallel Godot processes at a time; stdout/stderr redirect to per-game logs.
$queue = [System.Collections.Generic.Queue[object]]::new()
$pending | ForEach-Object { $queue.Enqueue($_) }
$running = @()
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    while ($queue.Count -gt 0 -and $running.Count -lt $Parallel) {
        $j = $queue.Dequeue()
        $log = [System.IO.Path]::ChangeExtension($j.Record, ".log")
        $proc = Start-Process -FilePath $Godot -ArgumentList $j.Args -PassThru -NoNewWindow `
            -RedirectStandardOutput $log -RedirectStandardError ([System.IO.Path]::ChangeExtension($j.Record, ".err.log"))
        $running += ,([pscustomobject]@{ Job = $j; Proc = $proc })
    }
    Start-Sleep -Milliseconds 250
    $still = @()
    foreach ($r in $running) {
        if ($r.Proc.HasExited) {
            $verdict = Read-GameVerdict $r.Job.Record
            if ($null -ne $verdict -and $verdict.Ok) { Write-Host "GAME OK: $($verdict.Summary)" }
            else { Write-Host "GAME FAILED: $($r.Job.Command)" }
        } else { $still += ,$r }
    }
    $running = $still
}

# Final tally over the WHOLE matrix (including previously-recorded games).
$results = foreach ($j in $jobs) {
    $verdict = Read-GameVerdict $j.Record
    [pscustomobject]@{
        Scenario = $j.Scenario; Policy = $j.Policy; Seed = $j.Seed
        Record   = $j.Record
        Ok       = ($null -ne $verdict) -and $verdict.Ok
        Command  = $j.Command
    }
}
$failed = @($results | Where-Object { -not $_.Ok })

$manifest = [ordered]@{
    batch_name   = $Name
    created_utc  = (Get-Date).ToUniversalTime().ToString("o")
    commit       = (git -C $repo rev-parse HEAD)
    dirty        = [bool](git -C $repo status --porcelain)
    scenarios    = $Scenarios
    policies     = $Policies
    seeds        = $Seeds
    turns        = $Turns
    games_total  = $jobs.Count
    games_run    = $pending.Count
    games_failed = $failed.Count
    results      = @($results | Select-Object Scenario, Policy, Seed, Record, Ok, Command)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $outDir "manifest.json")

Write-Host ("Batch '{0}' complete: {1}/{2} games OK; records in {3}" -f `
    $Name, ($results.Count - $failed.Count), $results.Count, $outDir)
if ($failed.Count -gt 0) {
    Write-Host "FAILED GAMES:"
    $failed | ForEach-Object { Write-Host "  $($_.Command)" }
    exit 1
}
exit 0
