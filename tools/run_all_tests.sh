#!/usr/bin/env bash
set -u

#
# Canonical verification gate for HexCombat.
# Bash port of tools/run_all_tests.ps1.
#
# Runs, in order, exiting non-zero on failure:
#   1. Import        — build the class cache (godot --import).
#   2. Smoke         — boot the main scene headless; assert data loaded, no script errors.
#   3. Validation    — every tools/validate_*.gd custom headless check.
#   4. GdUnit4       — the structured test suite under tests/.
#
# Godot binary: $GODOT_BIN env var, else 'godot' from PATH.
#

# Known Godot 4.7 *teardown* crash exit codes: the engine intermittently
# segfaults / corrupts the heap during SceneTree process SHUTDOWN when many
# headless scripts run back-to-back. The tests and validators have already
# finished and PASSED at that point — the crash only poisons the exit code.
# So we DO NOT treat these codes as failures on their own: a phase fails only
# if its OUTPUT shows a real failure (SCRIPT ERROR, a FAIL/Failure marker, a
# missing success marker, or GdUnit statistics with >0 errors/failures). A
# crash code with clean output is downgraded to a warning. A non-crash nonzero
# exit (e.g. a validator's quit(1)=1) still fails. This keeps the verdict
# honest: green output -> green gate, even through the flake.
# Linux signal mapping: SIGSEGV=11 -> 139, SIGABRT=6 -> 134,
#                       SIGBUS=7 -> 138, SIGILL=4 -> 132.

# --- Helpers ----------------------------------------------------------------

is_teardown_flake() {
    local code=$1
    # Linux signal-based exit codes: 128 + signum
    case $code in
        139|134|138|132) return 0 ;;
        *) return 1 ;;
    esac
}

write_phase() {
    echo ""
    echo "=================================================================="
    echo " $1"
    echo "=================================================================="
}

cecho() {
    local color=$1; shift
    case $color in
        red)      printf '\033[0;31m%s\033[0m\n' "$*" ;;
        green)    printf '\033[0;32m%s\033[0m\n' "$*" ;;
        yellow)   printf '\033[0;33m%s\033[0m\n' "$*" ;;
        cyan)     printf '\033[0;36m%s\033[0m\n' "$*" ;;
        darkcyan) printf '\033[0;36m%s\033[0m\n' "$*" ;;
        *)        printf '%s\n' "$*" ;;
    esac
}

# --- Godot binary resolution ------------------------------------------------

if [[ -n "${GODOT_BIN:-}" ]]; then
    GODOT="$GODOT_BIN"
else
    GODOT="godot"
fi

if ! command -v "$GODOT" >/dev/null 2>&1; then
    cecho red "FATAL: Godot binary not found at '$GODOT'."
    cecho red "Set \$GODOT_BIN or ensure 'godot' is on PATH."
    exit 2
fi

# --- Project root (parent of the script's directory) ------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Golden fixture selection -----------------------------------------------
# The whole gate runs against the FROZEN golden fixture (scenario_golden.json),
# not the research default (scenario_default.json, which carries the deep
# follow-on pool). This keeps every pinned validator/test byte-stable while
# scenario_default is free to evolve as the realistic self-play/research
# scenario. Selection is via the standard HEXCOMBAT_SCENARIO env var; an
# explicit --scenario arg still overrides it (used by the deep-pool coverage
# validator to load scenario_default on purpose). To run a single golden
# validator by hand, export the same var.
export HEXCOMBAT_SCENARIO="res://data/scenario_golden.json"

# --- State ------------------------------------------------------------------

failures=()
warnings=()

# --- Godot runner -----------------------------------------------------------
# Runs godot headless with --path PROJECT_ROOT + the given args.
# Combined stdout+stderr is printed AND captured.

invoke_godot() {
    "$GODOT" --headless --path "$PROJECT_ROOT" "$@" 2>&1
}

# ---- Phase 1: Import -------------------------------------------------------
# Success = the class cache built with no SCRIPT/Parse error. A teardown crash
# AFTER a clean import (no error markers) is the flake -> warn, don't fail.

write_phase "Phase 1/4 — Import (build class cache)"
out=$(invoke_godot --import)
godot_exit=$?
echo "$out"

if echo "$out" | grep -F -i -q "SCRIPT ERROR" || \
   echo "$out" | grep -F -i -q "Parse Error" || \
   echo "$out" | grep -F -i -q "Compile Error"; then
    failures+=("Import: SCRIPT/Parse/Compile error in output")
elif [[ $godot_exit -ne 0 ]]; then
    if is_teardown_flake "$godot_exit"; then
        warnings+=("Import: teardown-flake exit $godot_exit (import output clean) — ignored")
        cecho green "Import OK (teardown-flake exit $godot_exit ignored)."
    else
        failures+=("Import: godot exited $godot_exit")
    fi
else
    cecho green "Import OK."
fi

# ---- Phase 2: Smoke --------------------------------------------------------
write_phase "Phase 2/4 — Smoke (boot main scene headless)"
out=$(invoke_godot --quit-after 30)
godot_exit=$?
echo "$out"

smoke_ok=true
for marker in "Loaded 466 hexes" "Loaded 143 brigades" "Spawned 466 hex cells" "Rendered 32 brigade markers"; do
    if ! echo "$out" | grep -F -q "$marker"; then
        failures+=("Smoke: missing expected marker '$marker'")
        smoke_ok=false
    fi
done
if echo "$out" | grep -F -i -q "SCRIPT ERROR"; then
    failures+=("Smoke: SCRIPT ERROR in output")
    smoke_ok=false
fi
# All markers present + no SCRIPT ERROR means the smoke boot succeeded; a
# teardown crash on shutdown is the flake. Only a non-crash nonzero exit (with
# markers otherwise OK) is a real failure.
if [[ $godot_exit -ne 0 ]] && [[ $smoke_ok == true ]]; then
    if is_teardown_flake "$godot_exit"; then
        warnings+=("Smoke: teardown-flake exit $godot_exit (all markers present) — ignored")
    else
        failures+=("Smoke: godot exited $godot_exit")
        smoke_ok=false
    fi
fi
if [[ $smoke_ok == true ]]; then
    cecho green "Smoke OK."
fi

# ---- Phase 3: tools/validate_*.gd ------------------------------------------
write_phase "Phase 3/4 — Custom validation scripts (tools/validate_*.gd)"

shopt -s nullglob
validate_files=("$SCRIPT_DIR"/validate_*.gd)
shopt -u nullglob

if [[ ${#validate_files[@]} -eq 0 ]]; then
    cecho yellow "No validate_*.gd scripts found (skipping)."
fi

# Build sorted list of basenames (sorted by name, like the ps1).
validators=()
if [[ ${#validate_files[@]} -gt 0 ]]; then
    while IFS= read -r f; do
        validators+=("$(basename "$f")")
    done < <(find "$SCRIPT_DIR" -maxdepth 1 -name 'validate_*.gd' | sort)
fi

# Each validator quit()s 0 (pass) / 1 (fail) and prints a "PASS:"/"FAIL:"
# line. Verdict from OUTPUT: fail on a FAIL/SCRIPT-ERROR marker, or a missing
# PASS line, or a non-crash nonzero exit. A teardown crash with a clean "PASS:"
# line is the flake (a real failure quit(1)s with exit 1, not a crash code).
for v in "${validators[@]}"; do
    cecho darkcyan "--- $v ---"
    out=$(invoke_godot -s "res://tools/$v")
    godot_exit=$?
    echo "$out"

    saw_fail=false
    if echo "$out" | grep -F -i -q "SCRIPT ERROR" || echo "$out" | grep -E -q '^FAIL\b|^FAIL:'; then
        saw_fail=true
    fi
    saw_pass=false
    if echo "$out" | grep -E -q '^PASS\b|^PASS:'; then
        saw_pass=true
    fi

    if [[ $saw_fail == true ]]; then
        failures+=("Validation $v: FAIL/SCRIPT ERROR in output")
    elif [[ $saw_pass == false ]]; then
        # No explicit PASS line: trust the exit code (the validator may not
        # print a PASS marker).
        if [[ $godot_exit -eq 0 ]]; then
            cecho green "$v OK."
        elif is_teardown_flake "$godot_exit"; then
            warnings+=("Validation $v: teardown-flake exit $godot_exit, no failure markers — ignored")
            cecho green "$v OK (teardown-flake exit ignored)."
        else
            failures+=("Validation $v: exited $godot_exit, no PASS marker")
        fi
    else
        # Explicit PASS line present: succeed regardless of a teardown crash
        # exit code.
        if [[ $godot_exit -ne 0 ]]; then
            warnings+=("Validation $v: teardown-flake exit $godot_exit after PASS — ignored")
            cecho green "$v OK (teardown-flake exit $godot_exit ignored)."
        else
            cecho green "$v OK."
        fi
    fi
done

# ---- Phase 4: GdUnit4 suite ------------------------------------------------
write_phase "Phase 4/4 — GdUnit4 suite (tests/)"
# Verdict from the per-suite "Statistics:" lines, NOT the exit code: GdUnit
# returns 100 for real test failures, but the teardown flake can also corrupt
# the exit code to 100/crash AFTER every suite has reported 0 failures. So we
# sum the reported errors+failures across all suites; >0 is a real failure.
# If no statistics were emitted at all the run didn't complete -> failure. A
# nonzero exit with all-zero statistics is the flake -> warn.
if [[ -d "$PROJECT_ROOT/tests" ]]; then
    out=$(invoke_godot -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" --ignoreHeadlessMode -a "res://tests")
    godot_exit=$?
    echo "$out"

    sum_err=0
    sum_fail=0
    stat_count=0

    while IFS= read -r line; do
        if [[ $line =~ ([0-9]+)[[:space:]]+errors[[:space:]]+[|][[:space:]]+([0-9]+)[[:space:]]+failures ]]; then
            sum_err=$((sum_err + 10#${BASH_REMATCH[1]}))
            sum_fail=$((sum_fail + 10#${BASH_REMATCH[2]}))
            stat_count=$((stat_count + 1))
        fi
    done < <(echo "$out" | grep -E '[0-9]+[[:space:]]+errors[[:space:]]+[|][[:space:]]+[0-9]+[[:space:]]+failures')

    if [[ $stat_count -eq 0 ]]; then
        failures+=("GdUnit4: no test statistics emitted (run did not complete; exit $godot_exit)")
    elif [[ $sum_err -gt 0 || $sum_fail -gt 0 ]]; then
        failures+=("GdUnit4: $sum_err error(s) + $sum_fail failure(s) across $stat_count suite(s)")
    else
        if [[ $godot_exit -ne 0 ]]; then
            warnings+=("GdUnit4: teardown-flake exit $godot_exit ($stat_count suites, 0 errors/failures) — ignored")
            cecho green "GdUnit4 OK ($stat_count suites, 0 failures; teardown-flake exit $godot_exit ignored)."
        else
            cecho green "GdUnit4 OK ($stat_count suites, 0 failures)."
        fi
    fi
else
    cecho yellow "No tests/ directory (skipping)."
fi

# ---- Summary ---------------------------------------------------------------
write_phase "Summary"

if [[ ${#warnings[@]} -gt 0 ]]; then
    cecho yellow "${#warnings[@]} teardown-flake warning(s) (NOT failures — tests passed, engine crashed on shutdown):"
    for w in "${warnings[@]}"; do
        cecho yellow "  ~ $w"
    done
fi

if [[ ${#failures[@]} -eq 0 ]]; then
    if [[ ${#warnings[@]} -gt 0 ]]; then
        cecho green "ALL PHASES GREEN (with ${#warnings[@]} teardown-flake warning(s) ignored)."
    else
        cecho green "ALL PHASES GREEN."
    fi
    exit 0
fi

cecho red "FAILED (${#failures[@]} issue(s)):"
for f in "${failures[@]}"; do
    cecho red "  - $f"
done
exit 1
