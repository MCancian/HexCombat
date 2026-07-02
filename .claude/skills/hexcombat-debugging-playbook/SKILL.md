---
name: hexcombat-debugging-playbook
description: Symptom→triage table for HexCombat's known failure modes — teardown crashes, stale class cache, golden drift, fixture drift, nondeterminism, GdUnit quirks — with the discriminating experiment for each. Use the moment a gate phase goes red, a test flakes, or results look nondeterministic, BEFORE proposing a fix.
---

# HexCombat debugging playbook

Rule zero: **run the discriminating experiment before writing a fix.** Two incidents in this
project's history nearly shipped wrong fixes because the symptom pattern-matched a different cause
(details in `hexcombat-failure-archaeology`).

## Symptom → triage

| Symptom | First suspect | Discriminating experiment |
|---|---|---|
| Nonzero exit but output shows PASS / 0 failures | Godot 4.7 teardown crash (exit -1073741819, -1073740940, -1073741571, -1073740791) | Read the output. All markers present + no SCRIPT ERROR → it's the flake; the gate already warns-not-fails. Do NOT chase the exit code. |
| Validator/test fails right after you edited scripts | Stale class cache | Re-run `--import`, then the failing thing **standalone**. If green, it was the cache. |
| Same run gives different numbers across gate runs | Stale class cache masquerading as nondeterminism | Re-import, run the failing validator alone twice in fresh processes. Only if it still diverges is it real nondeterminism. (The census 20-vs-24 flake was cache, not state-bleed — a reset "fix" was rejected on this evidence.) |
| Golden values moved (casualties/feba) after a refactor | Your change consumed/reordered RNG draws or touched math | Diff for any new `dice` use, changed draw order, changed iteration order over dicts/arrays feeding rolls. Byte-stability is the refactor contract — fix the change, don't re-baseline. |
| `validate_fixtures.gd` red | JSON contract drift | Regenerate via `tools/export_llm_*.gd`; diff committed vs regenerated. Intended growth → commit regen + schema + keys. Unintended → your change leaked into serialization. |
| SCRIPT ERROR: could not resolve class / parse error on load | Missing import or a class_name collision | `--import` first. Then check for duplicate `class_name` or a renamed file whose `.gd.uid` is stale. |
| GdUnit reports 0 suites / no statistics | Run didn't complete (crash mid-run or bad path) | Re-run with output captured; look for the first SCRIPT ERROR — the suite list stops there. |
| A config value seems to have no effect | Silent-default dead config (`dict.get(key, default)`) | Grep the consumer for `.get(`; verify the producer's exact key spelling; check allowlist asserts. This is the exquisite-intel bug class — treat any "knob does nothing" as this until proven otherwise. |
| Windowed run looks wrong but gate is green | View-layer bug or projection issue | Screenshot via `tools/capture_screenshot.gd` and inspect; the gate doesn't cover pixels. |
| Nondeterminism only across machines/builds | Float or dict-ordering divergence | Compare `GameData.snapshot_state()` dumps; bisect by phase using the per-phase validators (`validate_headless_ijfs/antiship/offload`). |
| Brigade↔hex lookups inconsistent mid-investigation | Runtime index desync | Call `GameData.validate_runtime_indexes()` (read-only, returns violation strings). A debug-build assert already runs it at end of `resolve_turn`. |

## Bisecting a broken turn

The turn pipeline is IJFS → antiship → offload → move/commit → combat → frontline → cleanup.
Each phase has a standalone validator (`tools/validate_headless_<phase>.gd` or the phase's
`validate_*.gd`). Run them in pipeline order; the first red one owns the bug. For state questions,
snapshot before/after the suspect phase via `GameData.snapshot_state()` and diff.

## Traps that cost real time (each with its story)

- **Judging by exit code instead of output** → hours lost to the teardown flake before the gate
  learned to classify it. Always read output.
- **"Fixing" nondeterminism at the reset/state layer** → the phantom-reset proposal; the evidence
  (standalone re-runs stable) ruled it out before it shipped. Verify standalone first.
- **Trusting a doc's pinned numbers over the validator** → docs lag; validators are the truth.
- **Assuming a dict key exists** → exquisite intel dormant for the whole project. Fail loud.
- **Running the gate mid-edit** → half-imported cache produces phantom flakes. Finish the edit,
  import, then gate.
- **Using the nested TIV checkout as the oracle** — `TaiwanInvasionViewer` contains a stale nested
  copy of itself; always reference the top-level `src/`.

## When genuinely stuck

Two focused attempts at a red gate, then stop and surface to the user with the evidence
(per `hexcombat-change-control`). Record dead ends in `docs/RETROSPECTIVES.md` so the next agent
doesn't re-fight the battle.
