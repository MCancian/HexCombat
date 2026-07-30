---
name: hexcombat-validation-and-qa
description: What counts as evidence in HexCombat — the canonical gate's anatomy, the golden/certified inventory, byte-stability proofs, and the checklists for adding a validator, a GdUnit test, or a fixture. Use when verifying work, when a gate phase is red, or when new behavior needs a test.
---

# HexCombat validation & QA

## The canonical gate

`pwsh -File tools/run_all_tests.ps1` — four phases, exits nonzero on any failure:

1. **Import** — class-cache build; fails on SCRIPT/Parse/Compile errors in output.
2. **Smoke** — headless boot of `Main.tscn`; asserts the data-load markers
   (466 hexes / 143 brigades / 466 cells / 32 brigade markers) and no SCRIPT ERROR.
3. **Validators** — every `tools/validate_*.gd`, auto-discovered by filename (drop a new one in
   `tools/` and it's in the gate — no registration). Each prints `PASS:`/`FAIL:` and `quit()`s 0/1.
4. **GdUnit4** — all suites under `tests/`; verdict from the per-suite `Statistics:` lines.

**Verdicts come from OUTPUT, not exit codes**, because Godot 4.7 intermittently crashes during
teardown *after* everything passed (see `hexcombat-debugging-playbook`). Green output + crash exit
= warning. Never weaken this into ignoring real failures.

## What counts as evidence

- "Done" = **ALL PHASES GREEN**, run by you, output read by you. An implementer's report is not
  evidence; a partial run is not evidence.
- Refactors additionally prove **byte-stability**: golden values unchanged AND (for
  serialization-adjacent work) a fixture regenerated with/without the change hashes identical.
- Determinism claims are proven **cross-process**: run the validator twice in separate Godot
  processes and compare.
- Anything visual is verified visually (screenshot via `tools/capture_screenshot.gd`, Godot MCP,
  or the user) — headless green does not prove pixels.

## Certified / golden inventory

| Artifact | Pins | Where |
|---|---|---|
| Golden turn | seed 20260624 → fixed casualties/FEBA at the scripted beach-1 fight | `tools/validate_headless_turn.gd` — its PASS line is truth |
| Cleanup fingerprint | post-turn ownership/state hash | `tools/validate_cleanup.gd` |
| Golden victory e2e | deterministic terminal outcome (turn, winner, census) | `tools/validate_golden_victory.gd` — its PASS line is truth |
| Self-play | 4-turn full-game determinism + index health | `tools/validate_headless_selfplay.gd` |
| JSON fixtures | committed `docs/examples/*.json` must survive regeneration | the gate's "Fixture Generation & Drift Validation" phase in `tools/run_all_tests.py` — it re-runs the exporters, then `git diff --exit-code docs/examples/` |
| API contract | observation/action/result required keys ↔ schemas | `tools/validate_llm_api.gd` + `schemas/*.schema.json` |
| RNG purity | no global `randi()`/`randf()` in logic | `tools/validate_no_global_rng.gd` |

Never quote a pinned value in a doc — the validator's `PASS:` line is the source of truth; a
number copied into prose is stale the next time the golden re-baselines. Re-baselining is a
change-control event (`hexcombat-change-control`).

## Adding a validator (`tools/validate_<thing>.gd`)

1. `extends SceneTree`, do the checks in `_initialize()` (autoloads are up), print `PASS: <what>`
   or `FAIL: <why>` lines, `quit(0/1)`.
2. Fail loud and specifically — a validator that prints a vague FAIL costs the next agent an hour.
3. It is auto-discovered by the gate. Run it standalone first, then the full gate — but run it the
   way the GATE runs it, or its verdict is worthless:

   ```bash
   godot --headless --path . --import                    # class cache, after any new class_name
   HEXCOMBAT_SCENARIO=scenario_golden \
     godot --headless --path . --quit-after 300 -s res://tools/validate_<thing>.gd
   ```

   Both flags are load-bearing and `tools/run_all_tests.py` sets both (lines 22 and 123).
   **`HEXCOMBAT_SCENARIO=scenario_golden`**: omit it and every pinned validator loads
   `scenario_default` instead, so its pin compares two different scenarios and reports a FAIL that
   is nothing but your missing env var. This has burned two separate sessions — 2026-07-24
   (`validate_golden_victory`, `validate_cleanup`) and again 2026-07-27, where it cost three
   experiments chasing a phantom regression. **`--quit-after 300`** is the deadlock breaker: a
   validator whose *dependency* class fails to compile otherwise spins the SceneTree forever with no
   failure code.
4. Two layers, by purpose: **validators** = data contracts, cross-system invariants, golden pins,
   port equivalence (dependency-light, agent-friendly); **GdUnit** = unit logic, scene loading,
   input simulation, UI behavior.
5. **A validator that scans source must prove it still detects.** A regex silently stops matching
   and the gate goes green forever. `tools/validate_mutation_authority.gd` is the pattern: abstract
   illegal fixtures under `tools/fixtures/mutation_authority/` (suffix `.gdfixture`, so Godot's import
   and GdUnit's suite discovery never compile them) declare the rule each line must trigger, and the
   validator compares found-vs-expected **exactly** on every run. It separately generates in-memory
   probes for every REAL manifest claim and authority boundary, scans them against the REAL type
   corpus, and compares the manifest's claim identities with a committed non-authoritative pin. The
   separation is load-bearing: abstract fixtures prove write FORMS; real probes prove integration;
   the independent pin makes claim deletion/demotion fail instead of disappearing from generated
   expectations. Pair all source scanners with vacuity guards over files, symbols, and hits.

## Adding a GdUnit test (`tests/<thing>_test.gd`)

1. `extends GdUnitTestSuite`; name it `*_test.gd` so the suite runner picks it up.
2. New behavior ships with a test. If porting/adapting from a Python source case, mirror that case
   and name it so the lineage is findable.
3. Deterministic tests use `SeededDice` or `tests/helpers/ScriptedDice.gd` (scripted roll
   sequences) — never wall-clock, never global RNG.
4. Tests that drive the real scene use GdUnit's `scene_runner` on `Main.tscn` (see
   `movement_ui_test.gd`, `selection_test.gd` for the pattern).

## Fixtures

Committed under `docs/examples/`, regenerated ONLY via `tools/export_llm_*.gd`. The gate regenerates
them every run and then `git diff --exit-code docs/examples/`, so drift shows up as an unexpected
working-tree change rather than as a validator failure. If your change legitimately grows the JSON
contract: update schema + commit the regenerated fixture + update `REQUIRED_*_KEYS` in
`validate_llm_api.gd` (the duplication is a deliberate drift cross-check), in the same commit.

`tools/validate_skill_references.gd` keeps this file honest in one narrow respect: every fully
concrete `` `tools/…gd` `` path a skill cites must exist. Placeholders and globs
(`validate_<thing>.gd`, `validate_*.gd`) are skipped by design, and a line marked `(historical)` is
exempt.
