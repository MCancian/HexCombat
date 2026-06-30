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
2. **Per-ship-type mine neutralization likelihood.** The mine model maps likelihood by *category*, but
   the source varies within a category. Add a `mine_neutralization_likelihood` field to `ShipDef` +
   `ships.json` (defaulting to today's category values) so designers tune per hull. Additive; the
   category table stays as the fallback. (RETROSPECTIVES 2026-06-29 mine-geometry.)

2b. **Victory census counts present battalions, not OOB.** `GameState._taiwan_battalion_census()` sums
   `Brigade.get_battalion_count()` (OOB composition) for landed brigades, so battalions lost at sea
   before landing are still counted toward China. Count *surviving/present* battalions instead (the
   design's "battalions on Taiwan" means present). Belongs with the offload model. (PLAN.md 2026-06-29
   Victory conditions → OPEN.)

## High payoff, higher risk (do with attention)

3. **Typed `HexState` / `CombatSummary` Resources.** Replace the plain dicts threaded through
   `GameState`/`LLMGameAPI`/validators with typed Resources. Big readability + drift-safety win, but
   touches many call sites and carries golden-regression risk — do deliberately, one type at a time,
   re-running the golden invariant after each. NOT a free-model task. (Flagged across REFACTOR_NOTES M7
   and the handoff.)
4. **Debug-gated runtime-index auto-assert.** Wire `GameData.validate_runtime_indexes()` as a
   debug-only assert into the brigade mutators / end of `resolve_turn`. Catches index desync early, but
   a new hot-path assert can surface a latent *benign* transient desync and turn green tests red — do it
   with attention, not unattended. (Handoff "deliberately deferred".)

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
