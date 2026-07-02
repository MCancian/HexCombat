# Parameter sensitivity sweep (harness B5): vary ONE scenario knob across values, run the full
# seeded batch per value (common seed set = common random numbers), and report per-knob outcome
# deltas. Generalizes the old sweep_antiship_crossing pattern to any scenario key.
#
#   pwsh -File tools/run_sweep.ps1 -Name dos_sweep -Knob red_dos_start -Values 25,50,100,200 -N 20
#   pwsh -File tools/run_sweep.ps1 -Name arm_sweep -Knob victory.loss_check_arm -Values unconditional,after_first_landing
#
# -Knob takes a dot path into the scenario JSON (e.g. victory.loss_check_arm). Numeric value
# strings become numbers. Variant files are GENERATED artifacts under the sweep's output dir
# (never under data/scenarios/ — committed scenarios are authored, not generated); each is a
# copy of -BaseScenario with only the knob changed, named <knob>_<value>.json so the batch
# report's condition rows read as the sweep axis.
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Knob,
    [Parameter(Mandatory = $true)][string[]]$Values,
    [string]$BaseScenario = "data\scenario_default.json",
    [int]$N = 30,
    [int]$BaseSeed = 20260624,
    [int]$Turns = 30,
    [int]$Parallel = 4,
    [string[]]$Policies = @("selfplay_default"),
    [string]$Godot = "C:\Godot_v4.7-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
# `pwsh -File` passes "a,b" as ONE string — normalize comma-joined array params.
$Values = @($Values | ForEach-Object { $_ -split ',' })
$Policies = @($Policies | ForEach-Object { $_ -split ',' })
$repo = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repo "reports\batches\$Name"
$scenarioDir = Join-Path $outDir "scenarios"
New-Item -ItemType Directory -Force $scenarioDir | Out-Null

$basePath = if ([System.IO.Path]::IsPathRooted($BaseScenario)) { $BaseScenario } else { Join-Path $repo $BaseScenario }
$knobSlug = ($Knob -replace '[^A-Za-z0-9]', '_')

# One variant file per value: base scenario with only the knob (dot path) changed.
$variantPaths = foreach ($value in $Values) {
    $scenario = Get-Content $basePath -Raw | ConvertFrom-Json
    $typed = if ($value -match '^-?\d+$') { [int]$value } elseif ($value -match '^-?\d*\.\d+$') { [double]$value } else { $value }
    $segments = $Knob -split '\.'
    $node = $scenario
    for ($i = 0; $i -lt $segments.Count - 1; $i++) { $node = $node.($segments[$i]) }
    $node.($segments[-1]) = $typed
    $scenario.name = "$($scenario.name) [$Knob=$value]"
    $variant = Join-Path $scenarioDir ("{0}_{1}.json" -f $knobSlug, ($value -replace '[^A-Za-z0-9.-]', '_'))
    $scenario | ConvertTo-Json -Depth 10 | Set-Content $variant
    $variant
}

Write-Host "Sweep '$Name': $Knob over [$($Values -join ', ')] x $N seed(s); variants in $scenarioDir"
& pwsh -File (Join-Path $PSScriptRoot "run_batch.ps1") -Name $Name -Scenarios ($variantPaths -join ',') `
    -Policies ($Policies -join ',') -N $N -BaseSeed $BaseSeed -Turns $Turns -Parallel $Parallel -Godot $Godot
$batchExit = $LASTEXITCODE

& $Godot --headless --path $repo -s res://tools/make_batch_report.gd -- "--batch=$Name" | Select-String "REPORT"
Write-Host "Sweep report: $(Join-Path $outDir 'report.md')"
exit $batchExit
