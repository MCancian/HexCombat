---
title: "0015: Fully Parallelize Tests"
status: "✅ Shipped 2026-07-19"
created: "2026-07-19"
---

> **CLOSEOUT (2026-07-19).** Shipped. The three sequential-phase scripts (`.sh` inline logic,
> `.ps1` inline logic) collapsed into one unified `tools/run_all_tests.py` that fans validators
> and GdUnit suites across `os.cpu_count()` workers with isolated per-process `--user-data-dir`s;
> `.sh`/`.ps1` are now thin wrappers. Durable facts: `docs/DECISIONS.md` (2026-07-19 entry).
> Verified ALL PHASES GREEN on Linux; Windows `.ps1` wrapper unrun (pending-Windows-gate caveat,
> as with plan 0013). Implementation diverged from the sketch below: parallelism landed in Python
> (`concurrent.futures`) rather than bash `&`/`wait`, giving one code path for both boxes.

# Plan 0015: Fully Parallelize Tests

The HexCombat test suite currently takes ~40 seconds to run sequentially, which can be an annoying bottleneck in the local feedback loop. The goal is to fully parallelize the test suite execution.

## Phase A: Parallelize Custom Validators

The `tools/run_all_tests.sh` script executes all custom validators `tools/validate_*.gd` sequentially in Phase 3. These validators are stateless and purely data-driven.

1. Update Phase 3 to launch all `invoke_godot` commands into the background simultaneously (`&`).
2. Redirect their stdout/stderr and exit codes into a temporary directory (e.g. `mkdir -p .godot/test_results`).
3. Use `wait` to wait for all background jobs to finish.
4. Iterate over the saved logs to print the output in order and aggregate the pass/fail statistics using the existing flaky-teardown logic.

## Phase B: Parallelize GdUnit4 Suite

GdUnit4 runs test suites sequentially by default when passed a directory like `res://tests`. 

1. Gather all `tests/*.gd` files into an array.
2. Partition the array into N chunks (where N is derived from `$(nproc)`).
3. Spin up N concurrent GdUnit4 processes, passing each chunk using multiple `--add` flags or by creating temporary `GdUnitRunner.cfg` files.
4. Redirect outputs and wait for all jobs to finish.
5. Aggregate the summary line (parsing `[0-9]+ errors | [0-9]+ failures`) across all run outputs.

## Phase C: CI Integration

1. Integrate the new parallel test suite into the CI checks.
2. Verify that `tools/run_all_tests.ps1` (the Windows port) also receives parallelization support (e.g., using `Start-Job` or `ForEach-Object -Parallel`).

## Risks and Mitigation

- **Godot Cache Contention:** Godot might try to concurrently access `.godot/global_script_class_cache.cfg`. This is mitigated because `run_all_tests.sh` runs `godot --import` upfront, priming the cache before the parallel processes start.
- **Flaky Teardown Codes:** The parallel processes will still trigger the teardown crash flake randomly. We must ensure the stdout of every parallel process is properly analyzed with `is_teardown_flake()` just like the sequential runner does today.
