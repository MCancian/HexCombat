<#
.SYNOPSIS
    Canonical verification gate for HexCombat.
    Wraps the unified tools/run_all_tests.py script.
#>
[CmdletBinding()]
param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "" })
)
$ErrorActionPreference = "Stop"

if (-not [string]::IsNullOrEmpty($GodotBin)) {
    $env:GODOT_BIN = $GodotBin
}

$PythonBin = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } elseif (Get-Command python -ErrorAction SilentlyContinue) { "python" } else { "" }
if ([string]::IsNullOrEmpty($PythonBin)) {
    Write-Host "FATAL: Python interpreter not found." -ForegroundColor Red
    exit 2
}

& $PythonBin (Join-Path $PSScriptRoot "run_all_tests.py")
exit $LASTEXITCODE
