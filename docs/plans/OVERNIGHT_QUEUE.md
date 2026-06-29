# Overnight autonomous work queue

Drives the overnight `/loop`. **Orient each iteration:** `AGENTS.md`, `CLAUDE.md` (orchestrator role +
opencode usage), `docs/STATUS.md`, `docs/plans/port_audit.md`. You are the **orchestrator**; implement
via the `opencode` subagent (self-contained plan each time; tell it to follow `AGENTS.md`).

**Autonomy: MAXIMIZE (user-set).** Make reasonable judgment calls to keep moving; record each in
`PLAN.md` → Decisions. Only STOP (write to `/DECISIONS.md` and end the iteration) for a **truly
destructive/irreversible** action or a gate you **can't get green after ~2 focused attempts**. Never
commit `.mcp.json`. **Do NOT touch Track 5 graphics** — it needs visual verification, unsuitable for
unattended work.

## Known gate flakiness (retry policy)
A few `await`-signal GdUnit tests (`offload_calculator_test::test_day1_only_maneuver_bns_land`,
movement/`reachable_hexes_changed` awaits) intermittently time out (2s) under heavier suite load — they
pass in isolation and on re-run. **Policy:** if `run_all_tests.ps1` fails only on such an await-timeout
test, **re-run once**; a clean second run counts as green. A deterministic failure (same test, real
assertion) is a real break — fix it. (Hardening these awaits is queued under "exhausted" work below.)

## opencode invocation (Windows arg limits)
A long CLI prompt fails with "Argument list too long"; and `-f <file> "<msg>"` makes `--file` (an array)
swallow the message as a second file. **Use:** put the message FIRST, file LAST —
`opencode run -m … --dangerously-skip-permissions "short msg, see attached plan" -f "plan.md"` — or
just implement small/contained sub-tasks directly (faster than fighting the weak model + arg parsing).

## Per-iteration loop
1. Pick the next unchecked queue item below (top to bottom).
2. Implement via `opencode` (read the relevant `docs/systems/*.md` first; preserve ported math unless a
   re-baseline is the explicit point of the task).
3. **Verify yourself:** `pwsh tools/run_all_tests.ps1` → must end **ALL PHASES GREEN**. Review the diff
   for scope drift; exclude unrelated changes.
4. Commit (end message with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`). Push at milestones.
5. Update docs: `STATUS.md` (present tense, no dates), check the item off here + in `port_audit.md`,
   the relevant `docs/systems/*.md` (+ html mirror), `PLAN.md` → Decisions (why), `RETROSPECTIVES.md`
   (lessons + the opencode retrospective).

## Queue (in priority order)

- [x] **1. Wire `supply_effectiveness` into combat.** ✅ DONE 2026-06-29 — `GameState._inject_supply_effectiveness`; knob `red_out_of_supply_effectiveness`=0.5; tests added; gate green; golden unchanged. (`port_audit.md` "Supply-effectiveness → combat
  link".) Replace the hardcoded `1.0` in `CombatForces.maneuver_units` (`scripts/CombatForces.gd:20`)
  and `UnitManager.gd:31` with the real per-unit supply effectiveness derived from
  `GameState.supply_state` (out-of-supply Red BNs fight at reduced effectiveness, 0..1), mirroring TIV
  `boots_combat_service._inject_supply_effectiveness`. `CombatCalculator` already multiplies strength by
  it. Add a GdUnit test + extend a headless gate. **Re-baseline** the golden invariant if combat values
  shift (record old→new in `PLAN.md` Decisions + `validate_cleanup.gd` + `STATUS.md`).
  *Done when:* a depleted supply pool measurably lowers Red combat strength; gate green.

- [ ] **2. Apply IJFS→ground maneuver casualties** — large (Option B + detectability, settled
  2026-06-28); split into gateable sub-tasks (orchestrator call 2026-06-29):
  - [x] **2a. Persistent prior-turn activity flags on `Brigade`** ✅ DONE 2026-06-29 —
    `moved_last_turn`/`fought_last_turn` latched in `resolve_cleanup_phase`; `brigade_activity_history_test.gd`;
    gate green; golden unchanged (latch consumes no dice).
  - [x] **2b.** ✅ DONE 2026-06-29 — `IjfsLoaders.build_maneuver_targets(green_brigades)` (pure) mints
    `{brigade_id}-MU-{n}` per battalion instance + `MANEUVER_TYPE_MAP` profile + OOB metadata
    (battalion_id/brigade_id/to_number/unit_type). Added `Brigade.to_number`. `ijfs_maneuver_targets_test.gd`.
    NOT yet wired into the pipeline (2c/2d) → golden unchanged. Gate green.
  - [ ] **2c.** Detection/lethality bias: `mobility_multiplier` (less-mobile → more detectable),
    `posture="active"` for recently-active units, `hardness` (less-armored die more readily).
  - [ ] **2d.** Consume `maneuver_casualties`: remove struck battalions from the OOB before ground
    combat. Keep golden byte-stable (IJFS substream). Suppression reporting-only at first.
  Original item below: (`port_audit.md` "Ground-casualty IJFS↔OOB linkage".)
  Two halves: (a) **ID bridge** — ensure IJFS maneuver targets carry an OOB-matching `battalion_id`/
  `brigade_id` so `GameState._compute_ijfs_writeback` (`GameState.gd:547`) produces non-empty
  `maneuver_casualties`; (b) **consume** them — remove the struck battalions from the PLA/ROC OOB before
  ground combat resolves. Design settled **2026-06-28 (Option B + detectability)** — see `PLAN.md` Open
  Questions / `port_audit.md`; needs `moved_last_turn`/`fought_last_turn` on `Brigade`. Add gates.
  *Done when:* IJFS-destroyed maneuver battalions no longer fight in ground combat; deterministic; gate green.

- [ ] **3. Balance sanity pass (after EACH item above).** Run `tools/validate_headless_selfplay.gd` and a
  longer self-play game (extend turn count) on the changed values; confirm no crashes, deterministic,
  sensible outcomes. **Report only** — do not rebalance unprompted. Note observations in
  `RETROSPECTIVES.md`.

## When the queue is exhausted (still green)
Pick the next highest-value **headless-gateable** item: ADAPT items from `port_audit.md` **only if** a
concrete balance need is evident (else skip — they're "tie to a need, not speculative"); otherwise take
a REFINE item from `docs/plans/refactor_audit.md` (e.g. victory census counts *present* not OOB
battalions; typed `HexState`/`CombatSummary`). Keep maximizing autonomy; keep the gate green.
