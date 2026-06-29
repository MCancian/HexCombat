# Refactor / cleanup audit (Track 4)

Prioritized refactor candidates with payoff and risk. Read-only proposal — nothing here is applied
yet. Sources: `docs/REFACTOR_NOTES.md`, `docs/RETROSPECTIVES.md` "act later" items, and this session.

## High payoff, low risk (do first)

1. **`warmup_context` key-allowlist guard.** Every key in the IJFS `warmup_context` is read via
   `dict.get(key)` in `IjfsEngine.run_daily`; a typo silently yields `null` → that config goes dead
   with no error (this exact class of bug left exquisite intel dormant for the whole project). Add a
   one-line allowlist assert (or a typed `WarmupContext`) so a bad/missing key fails loud. Localized to
   the IJFS engine; no golden risk. (RETROSPECTIVES 2026-06-28 D3-D warmup.)
2. **Per-ship-type mine neutralization likelihood.** The mine model maps likelihood by *category*, but
   the source varies within a category. Add a `mine_neutralization_likelihood` field to `ShipDef` +
   `ships.json` (defaulting to today's category values) so designers tune per hull. Additive; the
   category table stays as the fallback. (RETROSPECTIVES 2026-06-29 mine-geometry.)

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
