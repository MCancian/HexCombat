# IJFS — Status

**D4 IJFS** (joint/air-missile fires) — detection → targeting → strike → suppression, with a
multi-day pre-invasion warmup (exquisite intel) on the first turn. Per-(TO,type) writeback feeds D3.
**IJFS now also attrits ground forces:** Green/ROC maneuver battalions are IJFS targets
(`build_maneuver_targets`); destroyed ones are removed from the OOB before ground combat
(`FiresPhases.apply_ijfs_maneuver_casualties`) — the D4-H ground-casualty linkage. Detectability is biased by
unit type (mobility/hardness via the `MANEUVER_TYPE_MAP` profile) and by recent activity: a brigade
that moved or fought last turn presents an `"active"` posture (`FiresPhases.update_maneuver_posture`), making its
maneuver units easier to detect. Each turn `FiresPhases.sync_maneuver_targets_to_oob` retires maneuver targets
whose battalions have died (IJFS or ground combat), so the air/missile campaign stops targeting units
that no longer exist — without disturbing detection continuity for survivors.
**CRBM heavy-volley maneuver attrition (plan 0009, USER call):** two coupled scenario
knobs in `ijfs_scenario.json` let Red spend its excess CRBM inventory on maneuver battalions —
`crbm_maneuver_rounds_override` (480) forces the volley size on every CRBM×Maneuver pairing
(depletion only), and `crbm_maneuver_strike_bonus` (0.15, USER-dialed
via `python3 tools/run_sweep.py --spec tools/sweeps/crbm_maneuver.json` — ~38% ROC maneuver-pool attrition over 40 turns) is the paired
lethality lever, synthesized into a strike modifier. Both synthesized by `IjfsLoaders`
(`apply_crbm_maneuver_*`), wired in `IjfsStateBuilder.build`. Detail: `docs/systems/ijfs/ijfs.md`
§4 Strike.
**MANPADS layer (USER design call — TIV-oracle divergence):** the ~2,500 Stingers are
per-TO container bins (category `MANPADS`, excluded from SEAD/AD-health) that intercept
low-altitude strikes (UAV/OWA/strike-aircraft munitions; ballistic/cruise immune) and contest
SEAD/strike squadrons island-wide, deteriorating via usage, bombardment, and TO ground losses
(`IjfsManpads.gd`; spec in `docs/systems/ijfs/ijfs.md` → "MANPADS layer"; surfaced as
`ijfs_summary.manpads`).
