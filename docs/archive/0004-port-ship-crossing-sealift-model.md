# 0004 — Port TIV ship-count & crossing model (follow-on sealift gap)

> **✅ Shipped 2026-07-12 (closeout).** Implemented as a cross-turn ship lifecycle + capacity-gated
> follow-on echelons + aggregate escort SAM magazine (USER scope: "Both"). Durable facts:
> `docs/systems/amphibious-offload.md` → "Sealift lifecycle"; `docs/DECISIONS.md` (2026-07-12);
> `docs/STATUS.md`; code headers in `scripts/resolvers/SealiftResolver.gd` + `SealiftState.gd`;
> knobs in `hexcombat-config-and-knobs`. Tests: `tests/sealift_resolver_test.gd`. The design/
> investigation body below is kept as history. USER-deferred: per-hull escort granularity +
> damage-driven repair delay (aggregate-per-type shipped).

**Status:** ✅ Shipped 2026-07-12 (was: Exploring) — the invasion stalled after ~turn 3; crossing
now resumes at turn 6 with follow-on echelons (roc_full_defense self-play, seed 20260624).

> This plan is a **work order for an agent**. It has two parts: an investigation of the source
> repo (TaiwanInvasionViewer, "TIV") and a port into HexCombat. Read the whole plan, then start
> with Part A. The copy-pasteable brief is the whole doc — no separate prompt needed.

## Goal

Sustain amphibious sealift across the game. Today HexCombat embarks a **single fixed reserve** that
drains in the first few turns and is never replenished, so once it empties no new PLA forces ever
cross — regardless of surviving hulls. Port TIV's ship-count / crossing model (stateful ships,
sorties/return trips, and/or scheduled follow-on echelons) so crossing tempo is driven by a real
sealift model instead of a one-shot pool.

## The gap in HexCombat today (verified 2026-07-11)

Crossing is **100% engine-scheduled** — there is no player "crossing" order (that part is correct):

- `scripts/LLMGameAPI.gd:68–86` accepts only `move`, `commit`, `end_turn`. No crossing/landing/
  reinforce action exists, so "Red never issues a crossing order" is by design, not a bug.
- `scripts/resolvers/AntishipResolver.gd:44` — *"The crossing wave = BNs still at sea. No wave →
  no anti-ship phase."* Each turn every battalion still in `ship_reserve` auto-crosses; survivors
  offload, losses drown.
- `ship_reserve` is **only ever reduced** (`GameState.gd:309, 438` reassign the shrunken
  `remaining_ship_reserve`). `_rebuild_ship_reserve()` runs **only at scenario load**
  (`GameState.gd:75`, def at `:514`; source `GameData._parse_red_ship_reserve`, `GameData.gd:227`).
  No code path appends to it mid-game; **no reinforcement / echelon / wave / return-trip scheduler
  exists anywhere in `scripts/`.**
- Scenario `data/scenarios/roc_full_defense.json` embarks `red_ship_reserve` = 4 PLA amphibious
  brigades — the *entire* invasion force. Only reinforcement-shaped key present is
  `red_ship_reserve`.
- Evidence run `reports/llm/game_20260711.viewer.json`: ships sent 148 → 75 → 17 → **0 for turns
  4–30**; ashore census peaks at 31 (turn 2) then attrites to 4 and plateaus. Hulls were NOT the
  binding constraint — the troop reserve was one-shot.

`scripts/ShipLoadingModel.gd` is a **stateless per-turn snapshot** (header cites source oracle
`TaiwanInvasionViewer src/services/manifest_allocator.py`). The stateful ship lifecycle that would
carry sealift across turns was not ported. `docs/archive/port_audit.md` §"Parked/Intentionally
skipped" is authoritative on what was left out on purpose — **reconcile against it before porting;
do not re-port anything it deliberately skipped without a USER call.**

## Part A — Investigate TIV (read-only)

Repo: `/var/home/qyfs/Projects/TaiwanInvasionViewer`. Onboarding: `docs/README.md` →
`docs/technical/ssot_map.md` (read first) → `docs/technical/codebase_map.md`. Then the phase docs:

- **Setup** (ship status, invasion plan, pre-landing config): `docs/PRD/Setup.md`,
  `docs/technical/api_setup.md`, `docs/technical/core_modules.md`.
- **Antiship** (crossing attrition): `docs/PRD/Antiship.md`, `docs/technical/calculator_antiship.md`,
  `src/services/antiship_crossing.py`, `src/services/manifest_allocator.py`.
- **Offload** (BNs ashore per turn): `docs/PRD/Offload.md`, `docs/technical/calculator_offload.md`,
  `src/services/offload_calculator.py`, `offload_orchestrator.py`.
- **Ship lifecycle across turns** (the likely missing piece): `src/services/ship_state_service.py`,
  `ship_transition_service.py`, `ship_readiness_policy.py`, `ship_capacity_service.py`,
  `ship_damage_service.py`, `individual_ship_service.py`, `ship_ammo.py`.
- **Multi-day tempo**: `docs/plans/Archive/ijfs-prelanding-days/`, and the antiship/offload archive
  plans under `docs/plans/Archive/`.

Answer, with file/line citations:

1. **How does TIV count ships across turns?** Are ships persistent stateful entities (readiness /
   damage / in-transit / returned states) or recomputed each turn?
2. **Do ships return and re-load (sorties over multiple days), or is lift single-shot?** What
   governs how many hulls are available to sail on a given day?
3. **How are follow-on troops scheduled?** Is there a troop reserve that replenishes, an echelon /
   wave timetable, or does capacity alone gate the tempo?
4. **What is the ship state lifecycle** (the transition service state machine) and how does damage
   feed back into future availability?
5. **What does HexCombat already have vs. what's missing** — map each TIV concept to its HexCombat
   counterpart (`ShipLoadingModel`, `AntishipResolver`, `OffloadResolver`, `ship_reserve`) and to
   the `port_audit.md` skipped list. Produce the delta to port.

## Part B — Port into HexCombat

Before writing code: `hexcombat-architecture-contract` (RNG flow, purity boundaries, autoloads),
`hexcombat-add-phase-resolver` (if this grows a new phase/state), `hexcombat-failure-archaeology`
(anti-ship/ship-loading history — don't re-fight settled battles), `hexcombat-change-control` (this
changes digest shape → **golden re-baseline required and allowed**, follow the tier + commit rules).

Likely shape (confirm against Part A findings, don't presume):

1. Give ships a persistent cross-turn state (readiness / in-transit / available) instead of the
   stateless snapshot, OR add a scheduled follow-on echelon feed into `ship_reserve` — whichever
   matches TIV and the USER fidelity call below.
2. New scenario config: reinforcement schedule / echelon timetable and/or ship sortie parameters.
   Add per `hexcombat-config-and-knobs` (scenario-parameter checklist) and
   `hexcombat-scenario-authoring`; give `roc_full_defense` a realistic multi-echelon force.
3. Wire through `AntishipResolver` / `GameState` / `OffloadResolver`, preserving determinism
   (`SeededDice`) and resolver purity. Re-baseline golden validators; add resolver tests for the
   new cross-turn behavior.
4. Verify: `bash tools/run_all_tests.sh` → ALL PHASES GREEN; then a research run
   (`hexcombat-research-runs`) showing sustained crossing past turn 3 with a plausible tempo.

## USER design checkpoints (surface; don't guess)

- **Fidelity/scope:** port TIV's full stateful ship lifecycle, or the minimal echelon-schedule that
  restores sustained sealift? (Recommend deciding after Part A quantifies the delta.)
- **Anything on `port_audit.md`'s intentionally-skipped list** that the port would reintroduce.
- Scenario force composition / reinforcement tempo is a wargame-design call — bring numbers to USER.

## Checklist

- [ ] Part A: TIV ship-count/crossing model documented with citations + the port delta
- [ ] USER checkpoint: fidelity/scope + port_audit reconciliation
- [ ] Ship cross-turn state and/or reinforcement schedule implemented (resolver-pure, deterministic)
- [ ] Scenario config + `roc_full_defense` multi-echelon force; config docs updated
- [ ] Golden re-baseline + new resolver tests; `run_all_tests.sh` ALL PHASES GREEN
- [ ] Research run confirms sustained crossing past turn 3
- [ ] Closeout: `docs/systems/*` (antiship/offload/ship model), STATUS bullet, DECISIONS entry,
      archaeology note if any incident; archive this plan
