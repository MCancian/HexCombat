# Refactor / cleanup audit (Track 4)

Prioritized refactor candidates with payoff and risk. Read-only proposal — nothing here is applied
yet. Sources: `docs/REFACTOR_NOTES.md`, `docs/RETROSPECTIVES.md` "act later" items, and this session.

## High payoff, low risk (do first)

1. ✅ **DONE 2026-06-30 — `warmup_context` key-allowlist guard.** `IjfsEngine.WARMUP_CONTEXT_KEYS` (the
   9 keys the engine reads) + `unknown_warmup_keys()`; `run_daily` asserts no unrecognized key is present,
   so a producer typo fails loud instead of going silently dead. `ijfs_warmup_context_guard_test.gd` pins
   the real producer↔consumer contract. No behavior change; golden byte-stable. _Noted-not-done (future
   refine): extend the allowlist to key→expected-type and also flag type mismatches — deferred as
   scope-creep (the documented bug was a misspelled key, which existence-checking fully covers; the
   producer is internal code, not user JSON)._ Original: every key read via `dict.get(key)` in
   `run_daily`; a typo silently yielded `null` → config went dead with no error (the bug class that left
   exquisite intel dormant for the whole project). (RETROSPECTIVES 2026-06-28 D3-D warmup.)
2. ✅ **DONE 2026-06-30 — Per-ship-type mine neutralization likelihood.** Optional
   `ShipDef.mine_neutralization_likelihood` (loaded from `ships.json` when present) that
   `GameState._mine_ship_meta` prefers over the per-category table; decoy override still wins, category
   is the fallback. Additive + behavior-preserving — no production hull sets it yet, so results are
   byte-identical (the field is the per-hull tuning hook; populate it when a balance need is concrete,
   per "tie to a need"). `mine_neutralization_override_test.gd`. _Original: likelihood mapped by category
   only, but the source varies within a category (LHD/LPD "Low" vs LST "High")._

2b. ✅ **DONE 2026-06-30 — Victory census counts present battalions, not OOB.**
   `GameState._taiwan_battalion_census()` now subtracts each brigade's still-at-sea battalions (tracked
   in `ship_reserve`) from its composition count, so a partially-landed brigade (hex_id set on its first
   BN landing) is no longer credited at full strength toward China. Golden terminal census china 36→20
   (4 amphibious brigades land 9 BNs each, 16 support BNs still at sea turn 1); winner unchanged (red).
   `victory_present_census_test.gd`. Golden byte-stable (census consumes no dice). _Original: summed
   `Brigade.get_battalion_count()` (full OOB) for any brigade with a hex, counting at-sea/lost BNs._

## High payoff, higher risk (do with attention)

3. ✅ **DONE 2026-06-30 — Typed `HexState` / `CombatSummary` Resources.** Done one type at a time,
   golden re-verified after each. **Type 1 `HexState`** (`scripts/model/HexState.gd`): replaced the
   `{owner, feba_km}` dict in `GameData.hex_states` across ~30 sites; `snapshot_state()` + LLM
   observation emit via `to_dict()`/typed reads, so JSON is unchanged. **Type 2 `CombatSummary`**
   (`scripts/model/CombatSummary.gd`): replaced the `_resolve_combat_at` dict; `last_combat_summaries`
   is `Array[CombatSummary]`, in-process consumers read typed fields, and every JSON boundary
   (`LLMGameAPI.last_combat`, `TurnEventLog` combat events, `TurnResult.to_dict`) emits via
   `to_dict()` with the former key order/types preserved. **Byte-stability proof:** regenerated
   `llm_result_after_turn.json` with and without the CombatSummary change → identical hash; golden
   `validate_headless_turn` casualties=3/feba=-0.96 byte-stable; full gate green (40 GdUnit + all
   validators), commits `388d4ae`+`d911010`. _Side finding: the committed `llm_result_after_turn.json`
   is **stale** — its antiship section predates the 2026-06-29/30 mine/antiship balance work (regen
   shows a 318/247-line drift that exists independent of this refactor). Left as a separate doc-hygiene
   fix, not bundled here._ (Flagged across REFACTOR_NOTES M7 and the handoff.)
4. ✅ **DONE 2026-06-30 (scoped) — Debug-gated runtime-index auto-assert.** Wired
   `GameData.validate_runtime_indexes()` as a debug-only assert at the **end of `resolve_turn`** (after
   cleanup recomputes ownership), gated on `OS.is_debug_build()` so the validator is never called in
   release. **Deliberately NOT in the per-mutator hot path** — that's the part the audit warned could
   surface benign transient mid-resolution desync and turn green tests red; the end-of-turn boundary is
   settled, so the assert held green across every turn-resolving path the gate exercises (golden turn,
   4-turn self-play, 40-turn victory e2e, all GdUnit suites). The hot-path variant remains intentionally
   un-done.

## Low priority / opportunistic

5. **Test-fixture helpers** — `CombatFixtures.gd` + a JSON golden-fixture format (scenario + expected
   rolls/losses/FEBA). Worth it once golden cases multiply; today there are few. (REFACTOR_NOTES M0.)
6. **Vestigial constants** — e.g. `PRE_INVASION_IJFS_DAYS` now only a fallback (warmup days come from
   the scenario JSON). Harmless; leave as the missing-config fallback rather than churn.
7. **Sweep harness shape** — `tools/sweep_antiship_crossing.gd` injects only the intel-bonus lever;
   generalize its grid to also sweep mine knobs (danger_radius, decoy mix) if calibration continues.

## Larger structural refactors (legibility + testability)

Proposed 2026-06-30 after the item-3 typed-Resource work, then **independently verified against the
actual code by a read-only review** (corrections folded in below — the line refs are the reviewer's).
Goal: a codebase a future agent can extend safely. **Sequence: 8 → 9 → 10** (cheap safety net first,
then proven low-risk DTO work, then the big structural change last). None implemented yet.

**Verified strength to PRESERVE (do not "fix"):** per-phase RNG isolation is already clean. IJFS and
antiship draw from independent derived substreams (`dice.derive("ijfs:…")` `GameState.gd:458-475`;
`dice.derive("antiship:…")` `:716-719`); **offload consumes no dice at all** (deterministic capacity
ordering — the `dice` param is accepted but never read, `:318/:340`); **combat is the SOLE base-stream
consumer** (`_resolve_combat_at` → `CombatCalculator.resolve_map_attack`, `:1217-1225`). Any extraction
must keep this topology. (This corrects the original proposal, which wrongly feared an offload↔combat
ordering coupling.)

8. ✅ **DONE 2026-06-30 — Schema ↔ code ↔ fixture drift gate.** Added `tools/validate_fixtures.gd`
   (auto-picked-up by `run_all_tests.ps1`): regenerates each committed `docs/examples/*.json` in memory
   and byte-compares (line-ending-normalized) against the committed copy, failing loud on drift. To keep
   a single source of truth (so the gate can't itself drift from the exporter), the fixture build logic
   was extracted into `tools/LLMFixtures.gd` and both the export tools and the gate build through it;
   exporters verified byte-stable after the refactor. Commit `b1f7244`. _Both committed fixtures were
   already current (the result one had just been regenerated), so no further drift cleanup was needed
   this time. The deriving-required-keys-from-types follow-up waits on item 9._ Original gap below:
   _Verified gap: schemas live
   as standalone `schemas/*.schema.json` with **no runtime validator**; `REQUIRED_*_KEYS` are
   hand-duplicated in `validate_llm_api.gd` (`:10-43`, key-set only — not shape); and **nothing in
   `run_all_tests.ps1` or any validator regenerates-and-byte-compares the `docs/examples/*.json`
   fixtures** — which is exactly why `llm_result_after_turn.json` rotted until the item-3 work caught it
   by hand. Fix: a new gated validator that runs the headless turn, exports each fixture to a temp path
   via the existing `tools/export_llm_*.gd`, and byte-compares against the committed copy (fail loud on
   mismatch) — auto-picked-up by `run_all_tests.ps1`. **Honest caveat:** wiring the gate is cheap, but
   the *first* regeneration may surface further stale drift to fix (as the antiship section already did);
   "cheap" applies to the gate, not necessarily the one-time cleanup.

9. ✅ **DONE 2026-06-30 — Typed phase-summary Resources (4 of the 5 fields; the 5th left untyped by USER
   call).** Converted four inline `GameState` summary dicts to typed `Resource`s with `to_dict()` at the
   JSON edge, one commit each, golden byte-stable after each (the `JSON.stringify(…, "\t")` exporter sorts
   keys, so only the key *set* + value types matter — both preserved): **`last_frontline_summary`** →
   `FrontlineSummary` (commit `b3473bd`); **`last_cleanup_summary`** → `CleanupSummary` (`360ec26`);
   **`last_antiship_summary`** → `AntishipSummary` (`206bc5c`); **`last_ijfs_writeback`** → `IjfsWriteback`
   (`f0112b0`, the riskiest — its internal cross-phase reads in `_apply_ijfs_maneuver_casualties` and
   `resolve_antiship_turn` are now typed-field accesses, + a `from_dict()` factory for the
   snapshot-mutate-reinject probe tools). `null` is the unresolved sentinel; EventBus signals + TurnResult
   + the event log + LLMGameAPI emit via `to_dict()`. Full gate green (40 GdUnit + all validators incl. the
   item-8 fixture-drift byte-compare); golden `validate_headless_turn` casualties=3/feba=-0.96 byte-stable
   throughout. **`last_ijfs_summary` deliberately LEFT as an untyped `Dictionary` (USER call 2026-06-30,
   YAGNI):** unlike the other four it is NOT an inline GameState dict but the ~21-key dynamic output of the
   faithful TIV-port `IjfsEngine.summarize_run` (with a *conditionally-present* `firing_capacity_utilization`
   key and many dynamic nested histograms/logs). Only 3 keys are ever read (once each, in
   `LLMGameAPI._ijfs_observation`); the rest is pass-through to JSON. A full-mirror Resource would be a
   fragile **second source of truth** for an engine port (silently dropping a key if `summarize_run` gains
   one) for read-safety on 3 fields — the same tradeoff the audit already declined for `combat_detail`
   below. The `resolve_supply_turn`/`resolve_offload_turn` return dicts are out of scope for the same
   reason (engine-output dicts / `DosConsumption`-built, not stored `last_*` summary fields). _Original gap
   below:_ Every consumer reads via `.get(key, default)`, so a producer key-rename silently degrades to a
   default.

10. ✅ **DONE 2026-07-02 — Decomposed the `GameState` god-object** *(multi-session arc, all four
    campaign phases complete)*. `GameState.gd` was **1,414 lines** orchestrating ~10 phases plus
    snapshot/play_turn; every phase's logic now lives in a pure `scripts/resolvers/` class,
    extracted one commit each, golden byte-stable (seed 20260624, casualties=3/feba=-0.96) + full
    gate green after every step. Public surface unchanged — test-called `GameState` methods
    remain as thin delegating wrappers.
    - ✅ **Phases A+B (2026-07-02):** 5 builders (`AntishipSystemsBuilder`, `ShipReserveBuilder`,
      `FleetBuilder`, `SupplyStateBuilder`, `IjfsStateBuilder`) + 2 dice-free resolvers
      (`SupplyResolver`, `FrontlineResolver`); data-path consts moved onto their only consumers;
      `tests/resolvers_test.gd` proves the isolation payoff (no autoloads).
    - ✅ **Phase C (2026-07-02):** the coupled middle, producer→consumer state map written first
      (PLAN.md → Decisions has the table): `CleanupResolver` (`16a1951`), `OffloadResolver`
      (`4d2be7a`), `AntishipResolver` + helper cluster (`c7dc344`, derived `antiship:%d`
      substream, draw sequence identical), `IjfsResolver` + cluster (`248ba6d`, derived
      `ijfs:%d:%d` substreams).
    - ✅ **Phase D (2026-07-02, `ac20077`):** the dice-consuming per-hex combat core →
      `CombatResolver.resolve_at` (pure; sole base-stream consumer isolated), plus
      `inject_supply_effectiveness`/`brigade_ids` statics behind delegating wrappers.
    - **What deliberately STAYS in `GameState` (scope decision, not leftover debt):**
      `_combat_contributors_for` (board/commitment gathering), `_apply_casualty`,
      `_apply_feba_retreats` + `_find_retreat_hex` (state application — per-hex casualty
      application interleaves with the next hex's contributor gathering, so a batch-pure combat
      phase would change ported behavior); all EventBus emits, `GameData` autoload access, lazy
      builds, and cross-phase field assignment (`ship_reserve`, `fleet`, `pending_lost_at_sea`,
      `antiship_systems`, `last_*` summaries, activity-flag latching) in the wrappers;
      `resolve_turn` as the explicit phase sequencer. Wrapper retirement (migrating test callers
      onto resolvers directly) was considered and deferred — the wrappers are 1–5 lines each and
      keep the public surface stable.
    - **DECIDED interface (user call 2026-06-30 — favor up-front effort for long-term legibility): pure
      `RefCounted` resolver classes, NOT new autoloads.** Each phase becomes a class with an explicit
      `resolve(game_data, dice, …) -> <TypedSummary>` signature; dependencies are visible in the
      signature and the unit is headless-testable in isolation. Autoloads were rejected as hidden globals
      that an agent must already know about — the opposite of legible. This matches AGENTS.md's existing
      rule for logic ("`RefCounted`/`static func`, no `Node` dependency, headless-testable"). `GameState`
      shrinks to a thin orchestrator that sequences the resolvers.
    - **The real risk is shared mutable state, not the method bodies.** ~8 fields flow *between* phases
      and must be threaded explicitly through the new interfaces: `ship_reserve`, `fleet`,
      `pending_lost_at_sea`, `antiship_systems`/`antiship_containers`, `last_ijfs_writeback`,
      `supply_state`, `game_over`/`winner`, and the per-brigade flags (`moved_this_turn`,
      `fought_this_turn`, `moved_admin_this_turn`, latched `moved/fought_last_turn`). Map every
      producer→consumer edge before moving code.
    - **Verified extraction order (corrects the original "cleanup first"):** start with the **data
      loading / rebuild helpers** (`_rebuild_ship_reserve`, `_rebuild_fleet`, `_rebuild_supply_state`,
      `_rebuild_ijfs_state`, `_ensure_antiship_systems`) — they have the fewest cross-phase deps — then
      the genuinely self-contained phases **`resolve_frontline_phase` (`:1051`, external polyline input
      only)** and **`resolve_supply_turn` (`:399`)**. `resolve_cleanup_phase` (`:963`) is **more** coupled
      than first thought (resets `antiship_systems` flags, reads `ship_reserve` for the census, latches
      brigade flags IJFS reads next turn) — do it later, not first. Re-run the golden after every step.

**Smaller item (verified YAGNI):** `combat_detail` stays an untyped `Dictionary` (`CombatResult.gd:16`,
`CombatSummary.gd:15`). It's built once (`CombatCalculator.gd:109`) and only ever serialized whole to
JSON — no code reads its nested fields in a typed way — so typing it would add 3-4 Resource classes of
boilerplate for zero read-site safety. Revisit only if per-casualty granularity becomes test-relevant;
the real drift risk for it is the schema boundary (item 8), not the GDScript type.

## Note

Most M0–M7 "act later" extracts (pure `TurnResolver`, per-turn event log, `play_turn` façade, typed
command/result wrappers) are **already done** via the Track-E AI-readiness arc — don't re-open them.
Items 1–4, **8**, **9**, and **10** are **done** — the refactor audit is fully discharged. The
forward plan lives in `docs/plans/BACKLOG.md` (Track B research harness is next).
