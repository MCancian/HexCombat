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

## Note

Most M0–M7 "act later" extracts (pure `TurnResolver`, per-turn event log, `play_turn` façade, typed
command/result wrappers) are **already done** via the Track-E AI-readiness arc — don't re-open them.
The live candidates are items 1–4 above.
