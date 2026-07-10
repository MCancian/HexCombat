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
| JSON fixtures | byte-compare of `docs/examples/*.json` | `tools/validate_fixtures.gd` + `tools/LLMFixtures.gd` |
| API contract | observation/action/result required keys ↔ schemas | `tools/validate_llm_api.gd` + `schemas/*.schema.json` |
| RNG purity | no global `randi()`/`randf()` in logic | `tools/validate_no_global_rng.gd` |

Never quote a pinned value in a doc — the validator's `PASS:` line is the source of truth; a
number copied into prose is stale the next time the golden re-baselines. Re-baselining is a
change-control event (`hexcombat-change-control`).

## Adding a validator (`tools/validate_<thing>.gd`)

1. `extends SceneTree`, do the checks in `_initialize()` (autoloads are up), print `PASS: <what>`
   or `FAIL: <why>` lines, `quit(0/1)`.
2. Fail loud and specifically — a validator that prints a vague FAIL costs the next agent an hour.
3. It is auto-discovered by the gate. Run it standalone first, then the full gate.
4. Two layers, by purpose: **validators** = data contracts, cross-system invariants, golden pins,
   port equivalence (dependency-light, agent-friendly); **GdUnit** = unit logic, scene loading,
   input simulation, UI behavior.

## Adding a GdUnit test (`tests/<thing>_test.gd`)

1. `extends GdUnitTestSuite`; name it `*_test.gd` so the suite runner picks it up.
2. New behavior ships with a test. If porting/adapting from a Python source case, mirror that case
   and name it so the lineage is findable.
3. Deterministic tests use `SeededDice` or `tests/helpers/ScriptedDice.gd` (scripted roll
   sequences) — never wall-clock, never global RNG.
4. Tests that drive the real scene use GdUnit's `scene_runner` on `Main.tscn` (see
   `movement_ui_test.gd`, `selection_test.gd` for the pattern).

## Fixtures

Committed under `docs/examples/`, regenerated ONLY via `tools/export_llm_*.gd`, byte-compared
every gate run. If your change legitimately grows the JSON contract: update schema + regenerate
fixture + update `REQUIRED_*_KEYS` in `validate_llm_api.gd` (the duplication is a deliberate
drift cross-check), in the same commit.
