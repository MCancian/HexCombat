---
name: hexcombat-gamestate-decomposition-campaign
description: COMPLETE 2026-07-02 — kept as the record of HOW the ~1,400-line GameState god-object was decomposed into pure resolver classes (refactor_audit item 10) — extraction order, per-step gates, fenced-off wrong paths. Consult when extracting further logic out of GameState or when a resolver-boundary question arises; for ADDING a new phase use hexcombat-add-phase-resolver instead.
---

# Campaign: GameState decomposition (refactor_audit item 10) — ✅ COMPLETE 2026-07-02

> All four phases (A–D) executed and green. This file is the permanent record of the method.
> The "what deliberately stayed in GameState" list is in `docs/archive/refactor_audit.md` item 10.

**Objective:** `GameState.gd` (~1,415 lines, 52 methods) becomes a thin orchestrator that
sequences pure `RefCounted` resolver classes in `scripts/resolvers/`, each headless-testable with
an explicit `resolve(<inputs>, dice) -> <TypedSummary>` signature. Highest-payoff, highest-risk
refactor in the backlog. Full spec: `docs/archive/refactor_audit.md` item 10; interface decided by
USER 2026-06-30 (docs/archive/PLAN.md → Decisions) — **do not relitigate: pure RefCounted resolvers, NOT
autoloads.**

## Success is measured, never judged by eye

After EVERY extraction, all three, in order:

1. `--import` → zero SCRIPT/Parse errors.
2. `tools/validate_headless_turn.gd` standalone (seed 20260624) — its `PASS:` line is the source
   of truth for the golden casualties/FEBA values, never a number copied into this doc.
   Byte-stable — if the validator's output moved, the extraction changed behavior: **revert and
   re-derive, never re-baseline.**
3. `pwsh -File tools/run_all_tests.ps1` → ALL PHASES GREEN (incl. `validate_fixtures`
   byte-compare and `validate_golden_victory`'s `PASS:` line for the terminal census).

One extraction per commit. If a step can't go green in two focused attempts → stop, record in
a Sketch plan in docs/plans/, surface to the user.

## The load-bearing constraints (why steps are ordered as they are)

- **RNG topology** (verified): offload consumes NO dice; IJFS/antiship use derived substreams;
  combat is the sole base-stream consumer. Extractions must not add/reorder/remove a single draw.
- **Public surface stays stable:** tests/tools call `GameState._rebuild_ijfs_state()`,
  `resolve_supply_turn()`, etc. directly. Extract the LOGIC; keep the `GameState` method as a
  thin delegating wrapper. No renames/deletions until a dedicated, attended cleanup step.
- **Purity boundary:** resolvers get data via params and return data/typed Resources. `EventBus`
  emits and `GameData`/`GameState` autoload access stay in the wrapper.
- **~8 cross-phase state fields** (`ship_reserve`, `fleet`, `pending_lost_at_sea`,
  `antiship_systems`/`antiship_containers`, `last_ijfs_writeback`, `supply_state`,
  `game_over`/`winner`, per-brigade activity flags) stay owned by `GameState`; resolvers receive
  them explicitly. Map every producer→consumer edge before moving a coupled phase.

## Phases

### Phase A — builders (pure constructors; safest; no dice) — ✅ DONE 2026-07-02
Extract in this order, one commit each (line refs may drift — locate by name):
1. `_ensure_antiship_systems` → builder returns `{systems, containers}`; lazy-guard stays in wrapper.
2. `_rebuild_ship_reserve` → returns the Array; wrapper assigns.
3. `_rebuild_fleet` → returns the Dictionary; wrapper assigns.
4. `_rebuild_supply_state` → returns fresh `SupplyState`; wrapper assigns.
5. `_rebuild_ijfs_state` → takes `antiship_containers` + Green brigades as params, returns
   `IjfsDailyState`; wrapper keeps `_ensure_antiship_systems()` ordering + `_ijfs_day = 0` reset.

### Phase B — dice-free resolvers — ✅ DONE 2026-07-02 (see `tests/resolvers_test.gd` for the isolation-test pattern)
6. `resolve_supply_turn` → `SupplyResolver.resolve(supply_state, units, moved_ids, engaged_ids,
   turn_number)`; mutating the passed `SupplyState` Resource is allowed; EventBus emit stays out.
7. `resolve_frontline_phase` → `FrontlineResolver` over the already-pure `FrontLineService`;
   `GameData.set_brigade_hex` application + emit stay in the wrapper.

**Gate B (decision point):** Phases A–B green + committed → the pattern is proven. Continue only
with full attention (not as unattended overnight filler).

### Phase C — the coupled middle (attended) — ✅ DONE 2026-07-02
(CleanupResolver 16a1951, OffloadResolver 4d2be7a, AntishipResolver c7dc344, IjfsResolver 248ba6d)
8. **Map first, move second:** write down (in the PR/Decisions entry) the producer→consumer table
   for the state each target touches.
9. `resolve_cleanup_phase` — deceptively coupled: resets antiship per-turn flags, reads
   `ship_reserve` for the census, latches `moved/fought_last_turn` that IJFS reads NEXT turn.
10. `resolve_offload_turn` — no dice but writes `GameData` placements + `ship_reserve`.
11. `resolve_antiship_turn` + its helper cluster (`_build_sent_fleet`, `_apply_ship_losses_to_fleet`,
    `_remove_bns_from_reserve`, `_mine_*`) — derived substream; keep the draw sequence identical.
12. `resolve_ijfs_turn` + its cluster (`_build_warmup_context`, `_update_maneuver_posture`,
    `_sync_maneuver_targets_to_oob`, `_apply_ijfs_maneuver_casualties`, `_compute_ijfs_writeback`).

### Phase D — combat core (last; sole base-stream consumer) — ✅ DONE 2026-07-02 (ac20077)
13. `_resolve_combat_at`'s dice-consuming core → `CombatResolver.resolve_at` (pure). **Scope
    judgment made here:** `_combat_contributors_for`, `_apply_casualty`, `_apply_feba_retreats`,
    `_find_retreat_hex` deliberately STAYED in GameState — they are state gathering/application,
    and per-hex casualty application interleaves with the next hex's contributor gathering
    (ported semantics), so a batch-pure combat phase would change behavior.
14. Final: `resolve_turn` reads as a legible sequence of resolver calls; wrapper retirement was
    deferred (test-called surfaces stay as delegating wrappers).

Each new resolver gets a focused GdUnit isolation test — that's the payoff of the interface.

## Fenced-off wrong paths (already lost time or explicitly rejected)

- **New autoloads** for phases — rejected by USER; hidden globals.
- **"Cleanup looks simple, extract it first"** — disproven by review; it's the most
  cross-coupled dice-free phase. It sits in Phase C for a reason.
- **Re-baselining the golden to make an extraction pass** — an extraction that moves the golden
  is wrong by definition.
- **Fixing a nondeterministic result by changing reset/state code** without first re-importing
  and re-running standalone — the census flake was a stale class cache (see
  `hexcombat-failure-archaeology`).
- **Typing `last_ijfs_summary`** — USER-decided untyped (item 9); leave it.
- **Batching multiple extractions into one commit** — kills bisectability; forbidden.

## Done when

`GameState.gd` is a thin sequencer; every phase's logic lives in a tested resolver;
`refactor_audit.md` item 10 marked done; Decisions entry records the arc; STATUS.md updated;
`hexcombat-add-phase-resolver` skill activated (its "not yet active" note removed) so future
phases follow the new template. Then update this skill's frontmatter description to note the
campaign is COMPLETE (keep it as the record of how).
