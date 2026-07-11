# 0003 — Combat-summary team attribution (attacker↔team seam)

**Status:** Sketch · **Priority:** Low — record-the-constant refactor with no payoff until a
counterattack mechanic exists; blocked on a USER design call

## Goal

`combat_summaries` should say which team held each combat role, so downstream consumers stop
re-deriving it from brigade-id conventions.

## The seam today

Attacker = Red is a game rule baked into the engine, not a per-combat determination:
`CombatResolver.resolve_hex_combat` hardcodes `inject_supply_effectiveness(attacker_units,
Brigade.Team.RED, …)` / defender GREEN, and `BatchReport` states the doctrine ("combat
(amphibious assault), so attacker_losses accrue to Red"). Because the summary never records the
team, every consumer re-derives it independently:

- viewer `tools/viewer/game_viewer.html` — `buildTeamIndex()` (brigade→team map from
  observations, `PLA-`/`BDE-` prefix fallback) for the casualty chart;
- bundler `tools/make_game_bundle.py` — `_digest_highlights` assumes side==Red ⇒ attacker;
- `scripts/BatchReport.gd` — accrues attacker_losses to Red by comment-documented convention.

All three are correct under current doctrine and stay correct as long as Green never attacks.

## USER design question (the blocker)

Is a Green counterattack / counterlanding mechanic ever wanted? Two outcomes:

- **No, doctrine is permanent** → close this plan as won't-do; optionally do the cheap
  summary-level stamp anyway if a digest re-baseline happens for other reasons (piggyback,
  never solo — the golden churn isn't worth a recorded constant).
- **Yes, someday** → team stamping is step 1 of that feature, in this order.

## Approach (only if the design call says yes)

1. **Stamp the summary**: `CombatSummary` gains `attacker_team` / `defender_team`;
   `CombatResolver.resolve_hex_combat` fills them at build time. Digest shape changes →
   golden re-baseline per `hexcombat-change-control` (allowed: additive field, engine math
   untouched).
2. **Migrate consumers**: viewer `computeCasualtySeries` reads the stamped team (keep
   `buildTeamIndex` as fallback for old bundles); `_digest_highlights` and `BatchReport`
   switch from convention to the field.
3. **Then** the actual mechanic: un-hardcode `inject_supply_effectiveness` teams, decide how
   the Red-only supply-pool asymmetry (`red_supply_pool` applies to the attacker) generalizes,
   new resolver tests. That's a `hexcombat-add-phase-resolver`-scale design, not this plan —
   spawn a fresh plan for it.

## Checklist

- [ ] USER call: counterattack mechanic ever on the table? (no → close won't-do)
- [ ] If yes: additive `attacker_team`/`defender_team` in `CombatSummary` + golden re-baseline
- [ ] If yes: consumers (viewer, bundler highlights, BatchReport) read the field
- [ ] If yes: new plan for the mechanic itself (supply asymmetry, resolver, tests)
