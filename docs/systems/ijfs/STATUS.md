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
**Air attrition is LOCAL to engagements (USER rulings, plan 0060 — TIV-oracle divergence).** Red
fields 498 reusable airframes (420 strike / 10 dedicated SEAD / 68 ISR); anti-radiation capability is
an expendable 192-missile munition rather than squadrons. An Organic strike is a package of four real
airframes drawn from the linked squadrons, and only aircraft that entered an envelope can die there:
same-TO SAMs engage the package on ingress, then MANPADS engages it if — and only if — the target is
a Maneuver Unit. MANPADS produces one of three mutually exclusive outcomes from one draw (kill /
abort-and-return-to-base / unaffected); the island-wide daily squadron contest it used to run is
deleted. SEAD resolves in three stages: expendable anti-radiation salvos, weighted IADS health, then
an aircraft assignment that costs Red strike airframes for the day. Every per-airframe loss
probability carries role exposure (altitude/profile) as well as RCS signature, cumulatively.
The prelanding warmup is a missile-only standoff campaign that exposes no aircraft at all.
(`IjfsSeadStage.gd`, `IjfsPackageIngress.gd`, `IjfsManpads.gd`, `IjfsAttritionProfile.gd`; spec in
`docs/systems/ijfs/ijfs.md` §3/§4 and → "MANPADS layer"; surfaced as `ijfs_summary.manpads`.)
**Mutation authority (plan 0046):** persistent IJFS state has one sanctioned writer,
`IjfsTransitions` — targets, munition magazines, squadron strength, the three `IjfsDailyState`
containers that persist across days, and the `ijfs_state`/`_ijfs_day` handles. Zero legacy writers;
no behaviour, RNG or golden change. MANPADS stock now lives on the typed
`IjfsTarget.manpads_remaining` (the `metadata` key is a serialization mirror). Unlike the other
aggregates the authority is called from INSIDE the pipeline stages, because IJFS draws dice
conditionally on state an earlier stage just wrote — rationale and rules in
`docs/systems/ijfs/ijfs.md` §9. `IjfsResolver` seeds unseeded MANPADS bins at the IJFS day boundary;
thereafter `IjfsManpads.systems_remaining` and `IjfsLedgers` report stock without applying state.
