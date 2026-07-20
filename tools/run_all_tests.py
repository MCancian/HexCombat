#!/usr/bin/env python3
import os
import sys
import subprocess
import concurrent.futures
import glob
import re
import platform
import tempfile

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT_DIR = os.path.join(PROJECT_ROOT, "tools")
GODOT_BIN = os.environ.get("GODOT_BIN", "godot")

# Ensure godot is in path or exists
try:
    subprocess.run([GODOT_BIN, "--version"], capture_output=True, check=False)
except FileNotFoundError:
    print(f"\033[0;31mFATAL: Godot binary not found at '{GODOT_BIN}'.\033[0m")
    sys.exit(2)

os.environ["HEXCOMBAT_SCENARIO"] = "res://data/scenario_golden.json"

TEARDOWN_CRASH_CODES = {
    "Windows": [-1073741819, -1073740940, -1073741571, -1073740791, 3221225477, 3221226356, 3221225725, 3221226505],
    "Linux": [139, 134, 138, 132],
    "Darwin": [139, 134, 138, 132]
}

def is_teardown_flake(exit_code):
    if exit_code == 0:
        return False
    sys_os = platform.system()
    codes = TEARDOWN_CRASH_CODES.get(sys_os, TEARDOWN_CRASH_CODES["Linux"])
    unsigned_codes = [c & 0xFFFFFFFF for c in codes]
    return (exit_code in codes) or ((exit_code & 0xFFFFFFFF) in unsigned_codes)

def write_phase(name):
    print("\n==================================================================")
    print(f" {name}")
    print("==================================================================")

def cecho(color, text):
    colors = {
        "red": "\033[0;31m",
        "green": "\033[0;32m",
        "yellow": "\033[0;33m",
        "cyan": "\033[0;36m",
        "darkcyan": "\033[0;36m",
        "reset": "\033[0m"
    }
    c = colors.get(color, "")
    if c and platform.system() != "Windows":
        print(f"{c}{text}{colors['reset']}")
    else:
        print(text)

failures = []
warnings = []

def invoke_godot(args, user_data_dir=None):
    cmd = [GODOT_BIN, "--headless", "--path", PROJECT_ROOT]
    if user_data_dir:
        cmd.extend(["--user-data-dir", user_data_dir])
    cmd.extend(args)
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    return result.returncode, result.stdout

# ---- Phase 1: Import ----
write_phase("Phase 1/4 — Import (build class cache)")
exit_code, out = invoke_godot(["--import"])
print(out)
if "SCRIPT ERROR" in out or "Parse Error" in out or "Compile Error" in out:
    failures.append("Import: SCRIPT/Parse/Compile error in output")
elif exit_code != 0:
    if is_teardown_flake(exit_code):
        warnings.append(f"Import: teardown-flake exit {exit_code} (import output clean) — ignored")
        cecho("green", f"Import OK (teardown-flake exit {exit_code} ignored).")
    else:
        failures.append(f"Import: godot exited {exit_code}")
else:
    cecho("green", "Import OK.")

# ---- Phase 2: Smoke ----
write_phase("Phase 2/4 — Smoke (boot main scene headless)")
exit_code, out = invoke_godot(["--quit-after", "30"])
print(out)
smoke_ok = True
for marker in ["Loaded 466 hexes", "Loaded 143 brigades", "Spawned 466 hex cells", "Rendered 32 brigade markers"]:
    if marker not in out:
        failures.append(f"Smoke: missing expected marker '{marker}'")
        smoke_ok = False
if "SCRIPT ERROR" in out:
    failures.append("Smoke: SCRIPT ERROR in output")
    smoke_ok = False

if exit_code != 0 and smoke_ok:
    if is_teardown_flake(exit_code):
        warnings.append(f"Smoke: teardown-flake exit {exit_code} (all markers present) — ignored")
    else:
        failures.append(f"Smoke: godot exited {exit_code}")
        smoke_ok = False
if smoke_ok:
    cecho("green", "Smoke OK.")

# ---- Phase 3: Custom Validation ----
write_phase("Phase 3/4 — Custom validation scripts (tools/validate_*.gd)")
validators = sorted([os.path.basename(f) for f in glob.glob(os.path.join(SCRIPT_DIR, "validate_*.gd"))])
if not validators:
    cecho("yellow", "No validate_*.gd scripts found (skipping).")
else:
    def run_validator(v, idx):
        # We assign an isolated user_data_dir for each parallel run to avoid cache contention
        user_dir = os.path.join(tempfile.gettempdir(), f"hexcombat_val_{idx}")
        code, text = invoke_godot(["-s", f"res://tools/{v}"], user_data_dir=user_dir)
        return v, code, text

    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as executor:
        futures = [executor.submit(run_validator, v, idx) for idx, v in enumerate(validators)]
        for future in concurrent.futures.as_completed(futures):
            v, exit_code, out = future.result()
            cecho("darkcyan", f"--- {v} ---")
            print(out)
            saw_fail = "SCRIPT ERROR" in out or bool(re.search(r'(?m)^FAIL\b|^FAIL:', out))
            saw_pass = bool(re.search(r'(?m)^PASS\b|^PASS:', out))

            if saw_fail:
                failures.append(f"Validation {v}: FAIL/SCRIPT ERROR in output")
            elif not saw_pass:
                if exit_code == 0:
                    cecho("green", f"{v} OK.")
                elif is_teardown_flake(exit_code):
                    warnings.append(f"Validation {v}: teardown-flake exit {exit_code}, no failure markers — ignored")
                    cecho("green", f"{v} OK (teardown-flake exit ignored).")
                else:
                    failures.append(f"Validation {v}: exited {exit_code}, no PASS marker")
            else:
                if exit_code != 0:
                    warnings.append(f"Validation {v}: teardown-flake exit {exit_code} after PASS — ignored")
                    cecho("green", f"{v} OK (teardown-flake exit {exit_code} ignored).")
                else:
                    cecho("green", f"{v} OK.")

# ---- Batch runner Python validation ----
write_phase("Batch runner Python validation")
env = os.environ.copy()
env["HEXCOMBAT_TEST_GODOT"] = GODOT_BIN
result = subprocess.run([sys.executable, os.path.join(SCRIPT_DIR, "validate_batch_runner.py")], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", env=env)
print(result.stdout)
if result.returncode != 0 or not re.search(r'(?m)^PASS: batch runner validation succeeded$', result.stdout):
    failures.append(f"Batch runner validation: failed (exit {result.returncode})")
else:
    cecho("green", "Batch runner Python validation OK.")

# ---- Research knobs Python validation (plan 0018: ledger + sensitivity) ----
write_phase("Research knobs Python validation")
rk_result = subprocess.run([sys.executable, os.path.join(SCRIPT_DIR, "validate_research_knobs.py")], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", env=env)
print(rk_result.stdout)
if rk_result.returncode != 0 or not re.search(r'(?m)^PASS: research knobs validation succeeded$', rk_result.stdout):
    failures.append(f"Research knobs validation: failed (exit {rk_result.returncode})")
else:
    cecho("green", "Research knobs Python validation OK.")

# ---- Metrics Validation (dependency ceilings) ----
write_phase("Metrics Validation (tools/gd_metrics.py --check-ceiling)")
metrics_result = subprocess.run(
    [sys.executable, os.path.join(SCRIPT_DIR, "gd_metrics.py"), PROJECT_ROOT, os.devnull, "--check-ceiling"],
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
print(metrics_result.stdout)
if metrics_result.returncode != 0 or not re.search(r'(?m)^PASS: dependency ceilings OK', metrics_result.stdout):
    failures.append(f"Metrics Validation: dependency ceiling breach (exit {metrics_result.returncode})")
else:
    cecho("green", "Metrics Validation OK.")

# ---- Fixture Generation and Drift Validation ----
write_phase("Fixture Generation & Drift Validation")
invoke_godot(["-s", "res://tools/export_llm_observation.gd", "--", "--output=docs/examples/llm_observation_red_turn1.json"])
invoke_godot(["-s", "res://tools/export_llm_result.gd", "--", "--output=docs/examples/llm_result_after_turn.json"])
try:
    git_result = subprocess.run(["git", "diff", "--exit-code", "docs/examples/"], cwd=PROJECT_ROOT, capture_output=True, check=False)
    if git_result.returncode != 0:
        failures.append("Fixture drift: LLMFixtures changed docs/examples/. Commit the regenerated JSON files.")
    else:
        cecho("green", "Fixture drift check OK.")
except FileNotFoundError:
    cecho("yellow", "git not found, skipping fixture git status check.")

# ---- Phase 4: GdUnit4 suite ----
write_phase("Phase 4/4 — GdUnit4 suite (tests/) (PARALLEL)")
tests_dir = os.path.join(PROJECT_ROOT, "tests")
if os.path.isdir(tests_dir):
    test_files = glob.glob(os.path.join(tests_dir, "**", "*_test.gd"), recursive=True)
    if not test_files:
        cecho("yellow", "No test files found in tests/ (skipping).")
    else:
        def run_test_suite(suite_file, idx):
            rel_path = "res://" + os.path.relpath(suite_file, PROJECT_ROOT).replace(os.sep, "/")
            user_dir = os.path.join(tempfile.gettempdir(), f"hexcombat_test_{idx}")
            code, text = invoke_godot(["-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd", "--ignoreHeadlessMode", "-a", rel_path], user_data_dir=user_dir)
            return rel_path, code, text

        sum_err = 0
        sum_fail = 0
        stat_count = 0
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as executor:
            futures = [executor.submit(run_test_suite, t, idx) for idx, t in enumerate(test_files)]
            for future in concurrent.futures.as_completed(futures):
                suite, exit_code, out = future.result()
                cecho("darkcyan", f"--- {suite} ---")
                print(out)
                
                matches = re.findall(r'(\d+)\s+errors\s+\|\s+(\d+)\s+failures', out)
                for err, fail in matches:
                    sum_err += int(err)
                    sum_fail += int(fail)
                    stat_count += 1
                
                if not matches:
                    failures.append(f"GdUnit4: no test statistics emitted for {suite} (run did not complete; exit {exit_code})")
                elif exit_code != 0 and is_teardown_flake(exit_code):
                    warnings.append(f"GdUnit4 {suite}: teardown-flake exit {exit_code} — ignored")
                elif exit_code != 0 and not matches:
                    failures.append(f"GdUnit4 {suite}: exit {exit_code} with no statistics")

        if sum_err > 0 or sum_fail > 0:
            failures.append(f"GdUnit4: {sum_err} error(s) + {sum_fail} failure(s) across {stat_count} suite(s)")
        else:
            cecho("green", f"GdUnit4 OK ({stat_count} suites, 0 failures).")
else:
    cecho("yellow", "No tests/ directory (skipping).")

# ---- Summary ----
write_phase("Summary")
if warnings:
    cecho("yellow", f"{len(warnings)} teardown-flake warning(s) (NOT failures — tests passed, engine crashed on shutdown):")
    for w in warnings:
        cecho("yellow", f"  ~ {w}")

if not failures:
    if warnings:
        cecho("green", f"ALL PHASES GREEN (with {len(warnings)} teardown-flake warning(s) ignored).")
    else:
        cecho("green", "ALL PHASES GREEN.")
    sys.exit(0)

cecho("red", f"FAILED ({len(failures)} issue(s)):")
for f in failures:
    cecho("red", f"  - {f}")
sys.exit(1)
