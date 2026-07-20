# HexCombat — plans index

Work orders for multi-session efforts. Each plan is a focused doc; **this index is the source
of truth** for status. Status vocabulary: `Sketch` → `Exploring` → `In progress` → `✅ Shipped`
→ `Superseded`.

**Plans are ephemeral by contract.** A plan holds the design, the checklist, and progress notes
*while the work is in flight*. It is not a reference: no durable fact may live only in a plan.

**Closeout rule** (enforced by `hexcombat-change-control` / `hexcombat-docs-and-writing`):
a plan is done only when its durable facts have landed in their canonical homes —
`docs/systems/<module>.md` updated, `docs/STATUS.md` bullet current, `hexcombat-failure-archaeology`
entry if there was an incident, a 3–5-line `docs/DECISIONS.md` entry — and the plan file gets a
3-line closeout header and moves to `docs/archive/`. If a future agent would need to read the
plan to act, the closeout wasn't done.

## Active

| # | Plan | Priority | Status |
|---|------|----------|--------|
| 0002 | [Per-hull escort magazines (D3-B3)](0002-per-hull-escort-magazines.md) | Low (needs ship-ammo subsystem) | Sketch |
| 0003 | [Combat-summary team attribution](0003-combat-summary-team-attribution.md) | Low (blocked on USER counterattack call) | Sketch |
| 0013 | [One home for scenario files](0013-scenario-files-one-home.md) | Low (hygiene; needs a Windows gate run to close) | Ready |
| 0016 | [Separate State Data from Autoload](0016-separate-state-data.md) | Medium (hygiene/architecture) | Superseded by 0014 |
| 0018 | [Research Knob Tracking](0018-research-knob-tracking.md) | Medium (Research visibility) | Sketch |
| 0020 | [Lowercase "red"/"green" team-token seam](0020-lowercase-team-token-seam.md) | Low (Tier A mechanical; Tier B needs USER design call) | Sketch |

## Archived

| # | Plan | Status |
|---|------|--------|
| 0019 | [Consolidate Brigade.Team→string converters](../archive/0019-team-string-seam.md) | ✅ Shipped 2026-07-20 — `Brigade.team_name(team)` static now owns the capitalized `"Red"/"Green"` mapping; six byte-identical local copies deleted and repointed; lowercase record serialization untouched; pure dedup, golden byte-stable; entry in `docs/DECISIONS.md` |
| 0017 | [Move order validation off push_error](../archive/0017-validation-errors.md) | ✅ Shipped 2026-07-20 — `OrderValidator.add_move_order`/`add_commit_order` (+ `GameState` wrappers) return a typed `OrderResult` (`ok`/`code`/`message`, `scripts/model/OrderResult.gd`) instead of `push_error`; LLM API surfaces the rejection reason; 11 GdUnit assertions moved off `is_push_error` to `code`; golden byte-stable; facts in `docs/STATUS.md`, `docs/DECISIONS.md`, `docs/systems/turn-engine.md` + `llm-api-selfplay.md` |
| 0015 | [Fully Parallelize Tests](../archive/0015-parallel-tests.md) | ✅ Shipped 2026-07-19 — unified `run_all_tests.py` using `concurrent.futures`, isolated Godot caches, wrapped `.sh` and `.ps1` |
| 0014 | [GameState dependency ceiling](../archive/0014-gamestate-dependency-ceiling.md) | ✅ Shipped 2026-07-19 — `GameState` split into a `GameStateData` value object + `static` `TurnConductor`/`GameStateBuilder`/`OrderValidator` (take `GameStateData`, never the autoload); deps 48→24, ceiling gated in `gd_metrics.py --check-ceiling`; absorbed plan 0016; facts in `docs/STATUS.md`, `docs/DECISIONS.md` |
| 0012 | [Unified sweep extraction & batch specs](../archive/0012-unified-sweep-extraction.md) | ✅ Shipped 2026-07-18 — canned sweeps unified on the batch backend (`run_sweep_cells.gd` deleted); Python metric extractors over standard game records (raw numbers, report owns formatting); `noop` matchup preserves dialed measurement semantics (byte-identical parity tables); `disable_phases` + `disable_antiship_systems` knobs; facts in `docs/STATUS.md` B5, `hexcombat-research-runs`, `hexcombat-config-and-knobs`, `docs/DECISIONS.md` |
| 0011 | [Disciplined Sweep Ecosystem](../archive/0011-disciplined-sweep-ecosystem.md) | ✅ Shipped 2026-07-18 — unified `run_sweep.py` orchestrator + `run_sweep_cells.gd` in-process backend; canned specs under `tools/sweeps/*.json`; deleted legacy bespoke sweep scripts; facts in `docs/STATUS.md`, `docs/systems/ijfs.md`, `docs/DECISIONS.md` |
| 0009 | [CRBM Maneuver Attrition Calibration Knob](../archive/0009-crbm-maneuver-attrition-knob.md) | ✅ Shipped 2026-07-17 — 480-round CRBM volley (`crbm_maneuver_rounds_override`) + lethality bonus (`crbm_maneuver_strike_bonus`, USER-dialed 0.15) vs maneuver units; follow-ups: warmup-casualty writeback fix (26/88→25/76), legacy mobile-cap removal, sweep-plumbing dedup; facts in `docs/systems/ijfs.md` §4, `hexcombat-config-and-knobs`, `docs/DECISIONS.md` |
| 0010 | [Hierarchical Deterministic RNG (Sub-streams)](../archive/0010-hierarchical-rng-substreams.md) | ✅ Shipped 2026-07-17 — per-hex combat substream (`dice.derive("combat:<turn>:<hex>")`); ijfs/antiship already derived, offload dice-free; 2 SeededDice pins re-baselined; facts in `docs/STATUS.md`, `docs/DECISIONS.md` |
| 0008 | [Immortal Support Units in Ground Combat](../archive/0008-immortal-support-units-combat.md) | ✅ Shipped 2026-07-17 — quarter-weight support casualties, unscreened strength 0.5; facts in `docs/systems/ground-combat.md`, `docs/STATUS.md`, `docs/DECISIONS.md` |
| 0009 | [Code-quality baseline + remediation](../archive/0009-code-quality-baseline.md) | ✅ Shipped 2026-07-16 — audit + standards skill (`hexcombat-code-quality`) + full remediation (6 splits, 19 tests, const hoists), all golden byte-stable; report in `docs/reports/`, deferred debt in BACKLOG Track F |
| 0007 | [Offload weight rebalance investigation](../archive/0007-offload-weight-rebalance-investigation.md) | ✅ Shipped 2026-07-16 — reframed the plateau to a force-commitment question (matrix was inactive); `roc_full_defense` given `scenario_default`'s deep pool; facts in `docs/systems/amphibious-offload.md`, `docs/DECISIONS.md` |
| 0006 | [Offload capacity gate (beaches + ports)](../archive/0006-offload-capacity-gate.md) | ✅ Shipped 2026-07-15 — infrastructure nodes + JLSF repair + cost matrix + occupancy valve + day-N carry-over; facts in `docs/systems/amphibious-offload.md` §9, `docs/DECISIONS.md` |
| 0004 | [Port TIV ship-count & crossing model (sealift gap)](../archive/0004-port-ship-crossing-sealift-model.md) | ✅ Shipped 2026-07-12 — cross-turn ship lifecycle + follow-on echelons + escort SAM magazine; facts in `docs/systems/amphibious-offload.md` §8, `docs/DECISIONS.md` |
| 0001 | [Crossing-lethality calibration (D3-D)](../archive/0001-crossing-lethality-calibration.md) | ✅ Shipped 2026-07-11 — dial-in facts in `docs/systems/ijfs.md`, `hexcombat-config-and-knobs`, `docs/DECISIONS.md` |

## Track-level forward work

See [BACKLOG.md](BACKLOG.md) — live tracks only (completed tracks live in `docs/STATUS.md` as
present-tense behavior, history in `docs/archive/`).

## Parked refinements (no plan until a concrete need)

One-liners; detail in `docs/archive/port_audit.md`:
- Flotilla composition nuances (unit of allocation for the missile pipeline — only with 0001).
- Front-line distribution at battalion granularity (with the D5-D draw UI, Track D).
- ShipLoadingModel per-type transport weight + amphibious-vs-cargo eligibility (exact-manifest
  calibration only).
- Deliberately NOT ported (TIV-specific): SQL/DB writeback, mine same-day re-preview baseline,
  Streamlit dashboards — list in `docs/archive/port_audit.md` §Intentionally skipped.
