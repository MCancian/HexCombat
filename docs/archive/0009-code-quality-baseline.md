# 0009 — Code-quality baseline + remediation

**Status:** ✅ Shipped 2026-07-16
**Closeout:** Audit + full remediation landed same session. Facts: report in
`docs/reports/2026-07-16-code-quality-baseline.md`, standards in
`.claude/skills/hexcombat-code-quality`, deferred debt in BACKLOG Track F, decision +
lessons in `docs/DECISIONS.md` / `docs/RETROSPECTIVES.md` (2026-07-16 entries).
**Priority:** High (USER: complete before research-game launches)

## Goal

Quality audit answered and enshrined (report + `hexcombat-code-quality` skill), then the full
debt list remediated: tests for uncovered builders/resolvers, the 6 oversized functions split,
gameplay magic numbers hoisted to named consts. All behavior-preserving: golden byte-stable
throughout, no re-baselines.

## Settled — do not relitigate

- Scope = full remediation this effort (USER call 2026-07-16, session question).
- Audit numbers + method: `docs/reports/2026-07-16-code-quality-baseline.md` (tool:
  `tools/gd_metrics.py`).
- Standards home: `.claude/skills/hexcombat-code-quality` (budgets apply to touched code only).
- No const→`data/*.json` knob promotion without a USER design call (change-control #7).
- Extraction rules: same math, same RNG draw order; helpers RECEIVE rolled results where
  possible; one file per commit; golden drift = bug in the change.

## Checklist

- [x] Audit measurements (gd_metrics.py, opencode test audit, gem sweep — spot-verified)
- [x] Commit A: report + skill + AGENTS/skills-README wiring + this plan + BACKLOG + tools/gd_metrics.py
- [x] Phase B tests: SupplyStateBuilder, ShipReserveBuilder, FleetBuilder, AntishipSystemsBuilder
- [x] Phase B tests: OffloadResolver, AntishipResolver (resolver-level, ScriptedDice)
- [x] Phase C split 1/6: `AntishipResolver.resolve` (157 ln, CC 19)
- [x] Phase C split 2/6: `OffloadResolver.resolve` (118 ln, CC 25)
- [x] Phase C split 3/6: `MineWarfareService.resolve_ship_losses` (118 ln, CC 22)
- [x] Phase C split 4/6: `IjfsEngagement.resolve_sead_engagement` (112 ln, CC 27 — RNG-heavy)
- [x] Phase C split 5/6: `CombatCalculator.resolve_map_attack` (130 ln, CC 11)
- [x] Phase C split 6/6: `AntishipCalculator.resolve_launch_attrition` (123 ln, CC 12)
- [x] Phase D: UnitStats.gd + CombatCalculator.gd literals → named const blocks;
      FrontLineService `6371.0` → `EARTH_RADIUS_KM`
- [x] Phase E: DECISIONS + RETROSPECTIVES + gd_metrics re-run (improvement proof) + closeout +
      archive move + push

Per-commit gate: `bash tools/run_all_tests.sh` ALL PHASES GREEN; Phase C/D additionally
`validate_headless_turn.gd` standalone, pinned values unchanged.

## Progress notes

- 2026-07-16: audit complete; gem-explore hallucination caught (invented 230-ln function in
  LLMGameAPI) — delegate claims require source verification before action.
