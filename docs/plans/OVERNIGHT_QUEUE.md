# Overnight autonomous work queue

Drives the overnight `/loop`. **Orient each iteration:** `AGENTS.md`, `CLAUDE.md` (orchestrator role +
opencode usage), `docs/STATUS.md`, `docs/plans/port_audit.md`. You are the **orchestrator**; implement
via the `opencode` subagent (self-contained plan each time; tell it to follow `AGENTS.md`).

**Autonomy: MAXIMIZE (user-set).** Make reasonable judgment calls to keep moving; record each in
`PLAN.md` → Decisions. Only STOP (write to `/DECISIONS.md` and end the iteration) for a **truly
destructive/irreversible** action or a gate you **can't get green after ~2 focused attempts**. Never
commit `.mcp.json`. **Do NOT touch Track 5 graphics** — it needs visual verification, unsuitable for
unattended work.

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

- [ ] **2. Apply IJFS→ground maneuver casualties.** (`port_audit.md` "Ground-casualty IJFS↔OOB linkage".)
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
