# IJFS — Joint/Air-Missile Fires (D4)

## 1. Purpose

The IJFS (Integrated Joint Fires Subsystem) models Red (China) long-range fires against Green
(Taiwan) targets across the pre-invasion air campaign and each invasion turn. The daily pipeline:
**ISR detection** → **targeting** → **engagement/SEAD** → **fires allocation** → **strike Pk** →
**hit/miss resolution** → **suppression**. A multi-day **warmup ramp** applies exquisite intel,
posture overrides, and capacity scaling before D-Day. Per-(TO,type) writeback feeds D3 (anti-ship
fires) and ground-casualty accumulation (open half).

## 2. Files & Responsibilities

| HexCombat file | Role | TIV oracle counterpart |
|---|---|---|
| `scripts/interleaved/IjfsEngine.gd` | Daily orchestration: the ORDER of a day, run context, continuity | `run_daily_ijfs.py`, `run_context.py` |
| `scripts/calc/IjfsLedgers.gd` | The day's summary and the ledger bundle (plan 0060) | `logging_utils.py` |
| `scripts/calc/IjfsStrikePhase.gd` | One strike pass, both times it runs: selection, budget, package, strike-log rows (plan 0060) | part of `run_daily_ijfs.py` |
| `scripts/calc/IjfsPackageIngress.gd` | Assembles a four-airframe Organic package and flies it in past SAMs and MANPADS (plan 0060 R8) | — (HexCombat divergence) |
| `scripts/calc/IjfsAttritionProfile.gd` | Per-airframe survivability: RCS signature x role exposure, shared by every path that can kill an aircraft (plan 0060 R2) | — |
| `scripts/interleaved/IjfsSeadStage.gd` | SEAD in three stages: anti-radiation salvos, weighted IADS health, aircraft assignment (plan 0060 R11) | — (HexCombat divergence) |
| `scripts/model/ijfs/IjfsAirPackage.gd` | The airframes flying one strike, or assigned to the day's SEAD | — |
| `scripts/model/ijfs/IjfsStrikeContext.gd` | One strike's day/phase/doctrine identity plus its package survivor fraction | — |
| `scripts/interleaved/IjfsDetection.gd` | Satellite (phase1) + aircraft (phase2) ISR detection | `detection.py`, `isr_sources.py`, `antiship_exposure.py`, `math_utils.py` |
| `scripts/interleaved/IjfsTargeting.gd` | Target filtering, pairing matching, doctrine priority, munition filter, exquisite intel | `targeting.py` |
| `scripts/interleaved/IjfsEngagement.gd` | One SAM being engaged; SAMs shooting back at a package; the post-phase-2 free shot | `engagement.py` |
| `scripts/interleaved/IjfsStrike.gd` | Strike probability (modifier system) and hit resolution | `strike_probability.py`, `strike_resolution.py` |
| `scripts/calc/IjfsFiringCapacity.gd` | `FiringCapacityBudget` (inorganic daily sortie cap) + `OrganicStrikeBudget` (strike-aircraft scaled) | `firing_capacity.py` |
| `scripts/calc/IjfsAdHealth.gd` | Taiwan AD health: per-category alive+unsuppressed fraction, SAM×radar effective health | `ad_health.py` |
| `scripts/calc/IjfsWarmup.gd` | Prelanding attrition-profile multiplier + capacity scaling | `warmup_profiles.py` |
| `scripts/model/IjfsDailyState.gd` | Mutable container threaded through one daily cycle; targets/munitions/squadron_force persist across days | `state.py` (IJFSDailyState, minus rng) |
| `scripts/loaders/IjfsLoaders.gd` | JSON loading, target expansion, anti-ship container→target builder, SAM score enrichment | `loaders.py` + `default_targets.py` |
| `scripts/model/ijfs/IjfsTarget.gd` | Resource model: target state fields + `to_dict()` | `state.py` (TargetInstance dataclass) |
| `scripts/model/ijfs/IjfsMunition.gd` | Resource model: munition inventory row | `state.py` (MunitionInventory dataclass) |
| `scripts/model/ijfs/IjfsPairing.gd` | Resource model: munition-target effect pairing | `state.py` (PairingRule dataclass) |
| `scripts/model/ijfs/IjfsSquadron.gd` | Resource model: squadron state (class, role, alive, losses) | `state.py` (SquadronState dataclass) |
| `scripts/interleaved/IjfsResolver.gd` | Pure resolver (Phase C): `resolve()` orchestrates the daily pipeline call (warmup loop or single plain day), `build_warmup_context()`, `compute_writeback()`, maneuver-target sync/posture/consume. Read its header for the purity boundary with `GameState`. | TIV warmup driver + write-outputs aggregation |
| `scripts/phases/FiresPhases.gd` | Thin wrapper (plan 0038): `resolve_ijfs_turn()` lazily builds `ijfs_state` then delegates to `IjfsResolver.resolve()`; `build_warmup_context()` delegates to `IjfsResolver.build_warmup_context()`. Owns the `EventBus.ijfs_resolved` emit and cross-turn field writes (`_ijfs_day`, `last_ijfs_summary`, `last_ijfs_writeback`). `GameState` forwards to it under the same method names. | — |

## 3. Daily Pipeline — Stage Order in `IjfsEngine.run_daily`

Mirrors `run_daily_ijfs.py`. Each stage consumes the shared `Dice` in sequence (order documented
in `IjfsEngine.run_daily`'s header comment — read it for the authoritative draw sequence):

1. **Warmup setup** (if warmup_context): posture override → exquisite-intel auto-detects → firing
   capacity scaling + release rules + munition filter
2. **AD health snapshot 1** (`taiwan_ad_health_before`)
3. **Satellite detection (phase 1)**: static/intel-locked targets auto-detected; other targets roll
   vs satellite-floor probability
4. **Pre-AD strike phase**: iterate `targets_to_attack`, select munition via doctrine, resolve
   strike, consume firing capacity
5. **AD health snapshot 2** (`taiwan_ad_health_after_missile_phase`)
6. **SEAD (three stages, on the day's air-engagement substream)**: expendable anti-radiation salvos
   against the richest active emitters -> weighted IADS health -> aircraft assignment and its
   destroy/suppress pass. Then, only once that pass is complete, per-SAM return fire against the
   assigned package.
7. **AD health snapshot 3** (`taiwan_ad_health_after_sead`)
8. **Aircraft detection (phase 2)**: ISR score = non-air sources + alive ISR aircraft ISR value /
   reference, clamped
9. **Post-AD strike phase**: repeat targeting with the organic (strike-aircraft) budget added. Each
   Organic strike assembles a four-airframe package, which same-TO SAMs and then MANPADS engage on
   ingress before it delivers at `survivors / package_size` effect
10. **Append final skips**: targets not attacked get a skip-log entry
11. **AD health snapshot 4** (`taiwan_ad_health_after`)
12. **Free shot**: remaining SAM health inflicts post-phase-2 attrition
13. **Summarize + build ledgers**

## 4. Detection / Targeting / Engagement / Strike — Key Formulas

### Detection (`IjfsDetection.gd`)

- **ISR source capability**: `floor + (initial - floor) * exp(-d * ln2 / half_life)` (exp_decay);
  also supports linear, weibull, logistic, gompertz, from_attrition, piecewise
  (`IjfsDetection.evaluate_isr_source`)
- **Satellite detection (phase 1)**: `p_detect = clamp(satellite_floor[mobility][posture])` — no ISR
  score contribution
- **Aircraft detection (phase 2)**: `p_detect = clamp(satellite_floor + base_prob * mobility_mult *
  posture_mult * weighted_isr)` where `weighted_isr = max(0, (non_air_score + aircraft_score) *
  contest_adjustment)`
- **Aircraft ISR raw**: `sum(alive * isr_value_per_aircraft) / reference_isr_sum` for ISR-role
  squadrons
- Static targets and `intel_locked` targets bypass rolls (auto-detected).
- **Green maneuver units (D4-H)**: `IjfsLoaders.build_maneuver_targets` emits one "Maneuver Units"
  target per ROC battalion instance; its `(mobility, hardness, detectability_active/hiding)` come from
  the `MANEUVER_TYPE_MAP` profile (less-mobile/softer → more findable/lethal). `posture` is set each
  turn by `IjfsResolver.update_maneuver_posture`, called by `FiresPhases.update_maneuver_posture`:
  a brigade that moved or fought last turn (the `moved_last_turn`/`fought_last_turn` flags) presents
  `posture="active"` — selecting the higher `detectability_active` label plus the active
  posture/satellite multipliers above — otherwise `"hiding"`. Because `ijfs_state` is built once
  per scenario, `IjfsResolver.sync_maneuver_targets_to_oob`, called by
  `FiresPhases.sync_maneuver_targets_to_oob`, also runs each turn to mark `destroyed` the maneuver
  targets in excess of the current OOB qty (battalions killed by IJFS or ground combat), so the
  campaign stops firing at units that no longer exist; it only sets `destroyed` (never
  resurrects), preserving survivors' detection continuity.

### Targeting (`IjfsTargeting.gd`)

- `targets_to_attack`: not destroyed AND detected_this_turn AND (if z_day/release_rules) release
  day met
- Pairing match: by source_target_id or (category, subcategory*, mobility*, hardness*) wildcard
  match
- Doctrine priority: `match_doctrine_rule` matched on category/subcategory/mobility/hardness →
  munition_priority list → fallback to compatibility order
- Exquisite intel: config-driven `initial_count * decay fraction` targets randomly selected (or
  deterministically) and `intel_locked = true`

### Engagement / SEAD (`IjfsEngagement.gd`)

- **SAM destroy**: `p_destroy = clamp(effective_power / (effective_power + sam_score), 0, 1)`
- **SAM suppress** (if not destroyed): `p_suppress = p_destroy * 0.4`
- **Anti-radiation salvo power** (`IjfsSeadStage` stage A): a flat `salvo_effective_power` of 4,
  against up to `salvos_per_day` active emitters in descending `sam_score`. It may home on an
  undetected emitter — the target signal is the emission.
- **Weighted IADS health** (stage B): `remaining_unsuppressed_sam_score / initial_sam_score` over
  every SAM instance. Weighted by capability, not by instance count.
- **Aircraft SEAD power** (stage C): `summed_sead_eff * (1 + avg_wvr * 0.1) * (1 - avg_rcs * 0.05)`
  over the ASSIGNED package only — dedicated airframes at their class `sead_eff`, ordinary strike
  aircraft at `ordinary_aircraft_sead_eff`. Multiplied by `sead_undetected_engagement` against
  emitters with `detected_this_turn == false`.
- **SAM return fire** (`resolve_package_return_fire`): one draw per surviving unsuppressed SAM
  against the exposed package; `u * N` picks the candidate and its fractional remainder is the hit
  roll. `p_loss = sam_package_return_fire_factor * sam_score * role_exposure * rcs_survival`,
  ASSERTED in [0, 1] rather than merely clamped, so a factor that would saturate the strongest SAMs
  fails loud instead of flattening the `sam_score` gradient.
- **Free shot** (post-phase-2): `loss_rate = clamp(raw_sam_health * 0.05, 0, 1)`, then the shared
  per-airframe modifiers.
- **Per-airframe modifiers** (`IjfsAttritionProfile`, every attrition path): role exposure
  (`isr 0.7 / sead 1.0 / strike 1.2`) x RCS survival `max(0.2, 1 + rcs * 0.1)`. CUMULATIVE — signature
  and flight profile are different survival advantages.

### Strike (`IjfsStrike.gd`)

- **Probability model**: `final = clamp((base + add_sum) * mult_product)` from
  `strike_probability_modifiers` in scenario config (an empty/absent modifier list yields `base` only).
- **Suppression** (if not destroyed): roll `probability_suppressed_if_not_destroyed` from pairing
- Data tables used: `pairings.json` (base probabilities per munition-target pair),
  `scenario.json` (`strike_probability_modifiers`)
- **Calibration knob** (plan 0001, crossing-lethality, USER dial-in 2026-07-11):
  `scenario.intel_locked_antiship_strike_bonus` (float; golden = 0.20) is a scalar add-bonus to
  strike probability against exquisite-intel-locked anti-ship coastal launchers (category
  `Anti-Ship Systems`, `intel_locked: true`). `IjfsLoaders.apply_intel_locked_strike_bonus`
  synthesizes it into a `strike_probability_modifiers` entry
  (`modifier_id: intel_locked_antiship_precision_strike`) at scenario-load time, so authors set one
  number instead of hand-writing the modifier's match/operation shape; 0.0 is a no-op. Paired with
  the companion lever `prelanding.intel.exquisite_intel.antiship.initial_count` (golden = 36), a
  plain data field read directly by `IjfsTargeting.apply_exquisite_intel` — no code promotion
  needed, editing the JSON value is sufficient. Together these give the USER-accepted 32.9% mean crossing loss
  on the post-plan-0004 81-BN sent-cohort wave (N=30-seed sweep; accepted 2026-07-18,
  superseding the ~25%-of-36-BN plan-0001 target). Sweep tool: `python3 tools/run_sweep.py --spec
  tools/sweeps/antiship_crossing.json`, grid-searches via `DataOverrides` per cell.
- **Calibration knob** (plan 0009, CRBM maneuver-attrition, USER batch re-dial pending):
  Two coupled scenario knobs in `data/ijfs/ijfs_scenario.json`:
  `crbm_maneuver_rounds_override` (int; shipped 480) and `crbm_maneuver_strike_bonus` (float; 0.15,
  USER-dialed 2026-07-17 via `python3 tools/run_sweep.py --spec tools/sweeps/crbm_maneuver.json` — N=24, default full-defense, ~38% of the
  124-battalion ROC maneuver pool killed over 40 turns; the bonus mainly amplifies the pre-D-day
  warmup, in-game attrition is detection-bound).
  `crbm_maneuver_rounds_override` forces `rounds_expended_per_engagement` to that value on every CRBM
  (`pch191_bre6_crbm` / `pch191_bre8_crbm`) × "Maneuver Units" pairing, replacing authored BRE6 48 /
  BRE8 12; applied by `IjfsLoaders.apply_crbm_maneuver_rounds_override`, called from
  `IjfsStateBuilder.build` after pairings + scenario load (the knob and pairings live in separate
  files). `rounds_expended` drives ONLY inventory depletion / affordability, NOT kill probability —
  so `crbm_maneuver_strike_bonus` is the paired lethality lever: an additive bonus to
  `probability_destroyed` for "Maneuver Units" struck by CRBM, synthesized by
  `IjfsLoaders.apply_crbm_maneuver_strike_bonus` into a `strike_probability_modifiers` entry
  (`modifier_id: crbm_heavy_volley_maneuver_bonus`, match `category="Maneuver Units"` + `munition_id`
  both CRBM ids). Rationale: lets Red spend excess CRBM inventory (BRE6 28800 ÷ 480 = 60, BRE8 7200 ÷
  480 = 15 engagements) for real maneuver attrition despite the one-attack-per-target-per-day rule.
  Both absent / 0.0 = golden-preserving no-op.

## 5. Warmup — Multi-Day Capability Ramp

The warmup runs before D-Day inside `IjfsResolver.resolve()` when `ijfs_day == 0` (the first call
`GameState.resolve_ijfs_turn` makes). Over `prelanding.days` (typically 4, falling back to
`IjfsResolver.PRE_INVASION_DAYS_FALLBACK` if the scenario omits it):

- Each day `i` (1-indexed) calls `IjfsResolver.build_warmup_context()` which:
  - Computes `profile_multiplier` via `IjfsWarmup.profile_multiplier` (even/front_loaded/back_loaded):
    `(2 * weight) / (total_days + 1)` where weight = total_days - x_day + 1 (front) or x_day (back)
  - Scales `red_firing_capacity` sorties per day by multiplier (`IjfsWarmup.scale_firing_capacity`)
  - Applies `posture_default_override`, `sead_enabled`, `ad_attrition_enabled`, `munition_filter`
    from scenario `prelanding.rules`
- Exquisite intel on day 1 (x_day) auto-detects a configurable count of Maneuver Units and
  Anti-Ship Systems, marking them `intel_locked` for that day. Decay reduces that count over
  subsequent warmup days (`IjfsTargeting.apply_exquisite_intel`).
- A fresh `SeededDice` substream per warmup day preserves reproducibility
  (`IjfsResolver._derive_day_dice`).
- Post-warmup turns run one plain `run_daily` call with `warmup_context = null`.

## 6. AD Health / Suppression

`IjfsAdHealth.compute_taiwan_ad_health` computes:

- **Category health** per AD type: `alive_unsuppressed / total` for each of Moveable SAMs, Static
  SAMs, Static Radars, Mobile Radars
- **Weighted averages**: `raw_sam_health` over SAM categories, `radar_health` over radar categories
- **Effective AD health**: `clamp(sam_weight_total * (raw_sam_health * radar_health) +
  radar_weight_total * radar_health, 0, 1)`

Snapshot before engagement: used by the pre-AD strike phase. Snapshot after missile phase: used by
SEAD return-fire. Snapshot after SEAD: used by post-AD strike. Final snapshot: used by free shot.

**Impact on D3 (anti-ship)**: suppressed Green systems are excluded from the AD health calculation.
`IjfsResolver.compute_writeback` reads cumulative `target.suppressed` from `ijfs_state.targets`
for each "Anti-Ship Systems" category target, producing `antiship_suppressed_by_type` by
(TO,type) key. `AntishipResolver.resolve` (called by `FiresPhases.resolve_antiship_turn`) applies
these to reduce `system.quantity` and `fire_pct`.

## 7. Writeback — Per-(TO,type) Outputs

`IjfsResolver.compute_writeback` aggregates:

| Ledger key | Source | Consumers |
|---|---|---|
| `antiship_destroyed_by_type` | Cumulative `target.destroyed` on Anti-Ship Systems targets | D3 `AntishipResolver.resolve`: reduces system quantity |
| `antiship_suppressed_by_type` | Cumulative `target.suppressed` on Anti-Ship Systems targets | D3 `AntishipResolver.resolve`: reduces fire percentage proportional to suppressed/available |
| `maneuver_casualties` | Strike log entries for "Maneuver Units" with `destroyed = true` (carry `brigade_id`/`battalion_id`/`unit_type` from target metadata) | **CLOSED (D4-H)** — `ForceTransitions.apply_battalion_casualties` (called by `FiresPhases.apply_ijfs_maneuver_casualties`) decrements the struck battalions' `qty` in the OOB before ground combat |
| `sam_destroyed` / `sam_suppressed` | Engagement log SEAD outcomes, both stages (each row carries its `stage`) | Summary only |

Anti-ship writeback keys use `AntishipCalculator.encode_key(to_number, type_id)` —
container-level targets carry `systems_represented` in metadata, so destroying one bin removes its
whole count from the firing plan.

## 8. Data Files

| File | Schema (first 20 lines) | Lines | Used by |
|---|---|---|---|
| `data/ijfs/targets_master.json` | Top-level `metadata` + `targets[]` array of target rows with `target_id, category, subcategory, quantity, mobility, detectability_*` | 2489 | `IjfsLoaders.load_targets` |
| `data/ijfs/red_munitions.json` | `metadata` + `munitions[]` with `munition_id, category, inventory_remaining_default, rounds_per_engagement_default` | 453 | `IjfsLoaders.load_munitions` |
| `data/ijfs/munition_target_pairings.json` | `metadata, target_effect_profiles[], pairings[]` — 52 profiles, 8 munitions, 333 pairings with `probability_destroyed, rounds_expended_per_engagement` | 10183 | `IjfsLoaders.load_pairings` |
| `data/ijfs/ijfs_scenario.json` | `schema_version: 1, china_isr_pools, detection_model, taiwan_air_defense_health, prelanding, red_firing_capacity, red_anti_radiation_sead, red_sead_assignment, isr_sources, target_release, strike_probability_modifiers, targeting_doctrine` | 574 | `IjfsLoaders.load_scenario` |
| `data/ijfs/red_air_oob.json` | `model_version, red_air_oob[]` — 10 rows with class/role/squadrons/aircraft_per_sqn. **498 airframes: 420 strike / 10 dedicated SEAD / 68 ISR** (plan 0060 R9/R11), pinned by `tools/validate_ijfs_data.gd` because every plan-0060 calibration is fitted against exactly this force | 15 | `IjfsLoaders.load_oob` |
| `data/ijfs/air_classes.json` | `model_version, reference_isr_sum, classes{}` — 10 classes with `kind, rcs, wvr, isr_value, sead_eff` | 16 | `IjfsLoaders.load_air_classes` |
| `data/ijfs/sam_capabilities.json` | `model_version, fallback_by_category, sam_score_by_subcategory` | 17 | `IjfsLoaders.load_sam_capabilities` |

## 9. State & authority

This subsystem owns the **`ijfs`** aggregate. Its designated authority is `IjfsTransitions`
(`scripts/transitions/IjfsTransitions.gd`, plan 0046) — the only production writer of `IjfsTarget`,
`IjfsMunition` and `IjfsSquadron`, of the three `IjfsDailyState` containers that persist across days,
and of the `ijfs_state` / `_ijfs_day` handles on `GameStateData`.

- **Outcome/receipt types:** none. Unlike the other aggregates the stages call the authority directly
  at their existing draw point rather than returning an outcome for a coordinator to apply — see
  below for why that is forced rather than chosen.
- **Manifest:** [tools/mutation_authority_manifest.json](../../../tools/mutation_authority_manifest.json).

**Rules:**
- Destruction is monotonic. No method in the authority clears `destroyed`, so a target cannot
  resurrect; suppression resets and detection passes leave it alone.
- Suppression is per-day and clears at the carry-over; destruction, detection continuity, munition
  inventory and squadron attrition carry forward.
- An exhausted magazine is a normal skipped attack, reported as `false`, never an error.
- Squadron strength stays within `0 <= alive <= initial`. Two loss counters with two lifetimes:
  `losses_today` is per-day (zeroed by `IjfsTransitions.carry_to_next_day` at the head of each day)
  and `losses_campaign` is the running total, so `alive == initial - losses_campaign`. Both ship in
  the `air_oob_after` ledger, which is `model_version` 4 for that reason.
- Two per-day AVAILABILITY ledgers, both reset at the day boundary and both serialized in
  `air_oob_after`: `rtb_today` (airframes a MANPADS abort drove home alive — its first runtime writer
  since the field was introduced, plan 0059 step 2 folded into plan 0060 R5) and
  `sead_assigned_today` (airframes booked to today's SEAD package, plan 0060 R11). Neither is a loss;
  both are bounded against `IjfsSquadron.available_today()`, which is `alive - rtb_today -
  sead_assigned_today` and is what every selection path must respect so an airframe cannot be
  committed twice in one day.
- MANPADS stock lives on the typed `IjfsTarget.manpads_remaining`;
  `metadata["systems_remaining"]` is a serialization mirror the authority keeps in step, because
  `metadata` is aliased live into the ledger rows. `IjfsResolver` eagerly seeds unseeded bins once
  at the IJFS day boundary through `IjfsTransitions`; `IjfsManpads.systems_remaining` is then a
  pure read, so `IjfsLedgers` remains in `scripts/calc/` without applying campaign state.

**Why this authority is called from inside the stages.** Every other aggregate applies once, at the
end, from a coordinator. IJFS cannot: its stages consume dice CONDITIONALLY on state an earlier stage
just wrote, and later stages choose which targets to iterate by reading it
(`IjfsTargeting.targets_to_attack` filters on `destroyed` / `detected_this_turn`; the MANPADS bins sort
on ready stock). Deferring application to end-of-day would change which targets are iterated and
therefore how many draws are consumed, which the golden pins forbid. The boundary this buys is a named,
checked, single-file writer — not a deferred one. That is also why the stage files stay in
`scripts/interleaved/` rather than moving to `scripts/calc/`; see the directory table in `docs/STATUS.md`.

## 10. TIV-Port Fidelity Notes

| Stage | HexCombat file | TIV file | Fidelity |
|---|---|---|---|
| **Orchestrator** | `IjfsEngine.gd` | `run_daily_ijfs.py` | **Close** — same phase order and the same draw-order comment block at the top of the file. Replaces file `write_outputs` with `IjfsLedgers.build_ledgers` returning a dict. Since plan 0060 the engine is the ORDER of a day only: the strike passes live in `IjfsStrikePhase` and the summary/record in `IjfsLedgers`. `EXQUISITE_INTEL_CATEGORIES` changed from dict to Array of pairs to preserve insertion order (RNG draw-order guarantee). |
| **Run context** | `IjfsEngine.make_run_context` | `run_context.IJFSRunContext.from_run_args` | **1:1** — same field logic (current_day, isr_day, z_day, x_day, is_warmup). |
| **Detection** | `IjfsDetection.gd` | `detection.py` + `isr_sources.py` | **1:1** — every `evaluate_isr_source` curve mode (exp_decay, linear, weibull, logistic, gompertz, from_attrition, piecewise) matches; `_apply_antiship_exposure_modifier` inlined rather than importing from `antiship_exposure.py`. |
| **Targeting** | `IjfsTargeting.gd` | `targeting.py` | **1:1** — `targets_to_attack`, `pairing_matches_target`, `select_munition_with_doctrine`, doctrine matching, `apply_exquisite_intel` all match signature-for-signature. |
| **Engagement** | `IjfsEngagement.gd` | `engagement.py` | **Diverged 2026-08-01 (plan 0060 R10/R11).** `p_destroy`, the suppression factor and the free shot still match. What no longer does: SEAD orchestration moved to `IjfsSeadStage` (three stages instead of one aggregate sweep), and the oracle's POOLED return-fire force tax — one draw per alive airframe in the whole OOB — was replaced by per-SAM fire against the exposed package only. |
| **SEAD stages** | `IjfsSeadStage.gd` | — | **HexCombat divergence** (plan 0060 R11): expendable anti-radiation salvos, weighted IADS health, then aircraft assigned in proportion to that health. No oracle counterpart. |
| **Air packages** | `IjfsAirPackage.gd`, `IjfsPackageIngress.gd` | — | **HexCombat divergence** (plan 0060 R8): an Organic strike is four real airframes drawn from real squadrons, so attrition is local and losses land on the squadron that supplied the airframe. No oracle counterpart. |
| **Strike Pk** | `IjfsStrike.gd` | `strike_probability.py` | modifier matching, `probability_context`, `evaluate_strike_probability` match. The TIV `_legacy_cap_probability` / `mobile_target_destroy_caps` path was dropped 2026-07-17 (never consumed once the scenario carries `strike_probability_modifiers`; see DECISIONS). |
| **Strike resolution** | `IjfsStrike.resolve_strike` | `strike_resolution.py` | **1:1** — inventory decrement, destruction roll, suppression roll, log shape identical. |
| **Firing capacity** | `IjfsFiringCapacity.gd` | `firing_capacity.py` | **1:1** — `FiringCapacityBudget` and `OrganicStrikeBudget` logic matches (floor, platform-kind health ratio). |
| **AD health** | `IjfsAdHealth.gd` | `ad_health.py` | **1:1** — categories, weighting, formula identical. |
| **Warmup profiles** | `IjfsWarmup.gd` | `warmup_profiles.py` | **1:1** — `profile_multiplier` and `scale_firing_capacity` identical. |
| **Daily state** | `IjfsDailyState.gd` | `state.py` | **Close** — same fields minus `rng` (caller passes Dice) and metadata/file paths moved to caller. `squadron_force` is `Array[IjfsSquadron]` rather than `SquadronForce` dataclass. |
| **Loaders** | `IjfsLoaders.gd` | `loaders.py` | **1:1** — same JSON shapes, expansion guard, target row→instance logic, pairing profile flattening, OOB→squadron expansion. |
| **Anti-ship target builder** | `IjfsLoaders.build_antiship_targets` | `default_targets.py` | **Adapted** — TIV uses `default_targets.py` + `services.antiship_containers`; HexCombat receives pre-built `containers` array (from `AntishipLoaders.load_containers`) and generates one target per (TO,type) container with `systems_represented` in metadata. |
| **Warmup driver** | `IjfsResolver.resolve` (called by `GameState.resolve_ijfs_turn`) | TIV warmup driver (standalone) | **1:1** — multi-day loop, `carry_to_next_day` between days, SeededDice substream per day. |
| **Writeback** | `IjfsResolver.compute_writeback` | TIV `write_outputs` aggregation | **1:1** — anti-ship writeback reads cumulative target state (not per-day delta), keyed by (TO,type). |

### Open Questions

1. **✅ Maneuver-casualties linkage CLOSED 2026-06-29 (overnight 2b–2d).** Green/ROC maneuver battalions
   are now generated as IJFS targets (`IjfsLoaders.build_maneuver_targets`, wired in
   `FiresPhases.rebuild_ijfs_state`), struck, written back (`maneuver_casualties` populates), and
   **consumed** (`FiresPhases.apply_ijfs_maneuver_casualties` removes struck battalions from the OOB before ground
   combat). Tests: `ijfs_maneuver_targets_test.gd`, `ijfs_maneuver_consume_test.gd`. The 2c-ii
   detection/lethality bias is the remaining refinement. _Historical (now resolved) description:_
   (a) **No ID bridge** — `maneuver_casualties` is accumulated in `_compute_ijfs_writeback`
   (`GameState.gd`, a faithful port of `ijfs_maneuver_writeback_service`), but at runtime it is
   **empty** because IJFS maneuver targets carry no `battalion_id`/`brigade_id` matching the PLA/ROC OOB.
   (b) **No consumer** — even when populated, nothing applies it: only `antiship_destroyed_by_type` is
   consumed (`GameState.gd`, feeds the D3 firing plan); `maneuver_casualties` is merely exposed in
   the LLM observation (`LLMGameAPI.gd`). So IJFS air/missile kills do **not** reduce the brigades
   that fight in ground combat. (See `docs/archive/port_audit.md` — "Ground-casualty IJFS↔OOB linkage",
   status ADAPT; design settled 2026-06-28.)

2. **Squadron force shape**: HexCombat passes `Array[IjfsSquadron]` directly where TIV wraps it in
   a `SquadronForce` dataclass with a `.squadrons` attribute. All call sites handle both
   (`_force_squadrons` in IjfsDetection.gd), but the dual-path is a divergence surface.

3. **Category groups**: `category_groups.py` (operational_chart_categories,
   static_chart_categories) is not ported — these are chart-filtering constants only, not part of
   the simulation pipeline. Port if a reporting view needs them.

## MANPADS layer (2026-07-10 — deliberate divergence from the TIV oracle)

USER design call (2026-07-10) after the "2,496 Mobile SAMs destroyed" finding (see
`hexcombat-failure-archaeology`): the oracle modeled ~2,500 individual Stinger MANPADS as
SEAD-engageable Mobile-SAM targets — SEAD annihilated them all on the first air-phase turn with
p≈1 each, poisoning every report while contributing nothing (excluded from AD health, score-0
return fire).

**Model now:** Stingers are 50 container bins of 50 launchers each (category `MANPADS`,
`data/ijfs/targets_master.json`, per-TO: TO2 500 / TO3 1000 / TO4 500 / TO5 500; mutable
`systems_remaining` seeded from `systems_represented`). The category sits OUTSIDE
`IjfsEngagement.SAM_CATEGORIES` and `IjfsAdHealth.AD_CATEGORIES`: SEAD cannot hunt passive-IR
shoulder launchers. Instead (`scripts/interleaved/IjfsManpads.gd`, wired in `IjfsEngine.run_daily`):

1. **Package engagement** (plan 0060 R5/R6/R12, USER rulings 2026-08-01) — the ONE surface. A
   MANPADS engagement exists only when a four-airframe MANNED package strikes a target whose
   category is exactly `Maneuver Units`, in a TO that still holds ready launchers, flying a munition
   its capacity row marks `manpads_eligible`. In practice that is `strike_aircraft_medium` alone:
   Attack UCAV packages are marked ineligible, and `owa_drone_small` has no Maneuver-Unit pairing.
   MANPADS therefore protects no SAM, radar, infrastructure or anti-ship target, and never touches
   ISR, SEAD or unmanned strike aircraft.

   The engagement consumes EXACTLY ONE draw and produces exactly one outcome. `u * N` picks the
   candidate from the surviving package and the fractional remainder of the same product is that
   candidate's outcome roll, clamped at the inclusive-1.0 boundary:
   - **killed** — `p = threat x manpads_attrition_factor x vuln x role_exposure x rcs_survival`;
     one member dies and the survivors press at reduced effect;
   - **aborted** — `p = threat x 0.15 x vuln` (no per-airframe modifier: being driven off is about
     the launcher's presence, not the airframe's signature); every survivor books `rtb_today` and
     today's strike is denied;
   - **unaffected** — the package presses at full strength.

   Kill and abort are mutually exclusive, so attrition is not a rider on a successful abort, and
   their bands are asserted to sum to at most 1.

   **What this replaced.** Until 2026-08-01 MANPADS had TWO surfaces: an interception roll against
   every low-altitude strike on any target, and an island-wide daily contest that taxed every SEAD
   and strike squadron for being in the campaign at all. Both are deleted; `CONTESTED_ROLES` and the
   `manpads_contest_log` ledger went with them, and `tools/validate_ijfs_data.gd` sweeps `scripts/`
   and `tools/` to keep the ledger key at zero references.

2. **Ledger** — `manpads_intercept_log` is the single MANPADS event stream, one row per engagement
   carrying target/TO/munition, the package before and after, the outcome, attributed losses, the
   RTB count and whether the strike executed. The summary reports `attempts` / `kills` / `aborts` /
   `unaffected` explicitly, and keeps `interceptions = kills + aborts` as the compatibility total
   the narrative reads.

3. **Deterioration** — three drains: usage (3 missiles per engagement, whatever the outcome, lowest
   `target_id` bins first), bombardment (bins stay strikeable through the normal
   pairing path — 6 pairings retargeted to category `MANPADS`), and ground losses
   (`IjfsResolver.sync_manpads_to_oob`: each TO's pool is capped at
   `systems_represented × alive/total` of that TO's Maneuver-Unit targets — MANPADS ride with the
   infantry; zero dice, idempotent, monotonic).

Summary surface: `ijfs_summary.manpads` (`ready_systems_by_to`, `attempts`, `kills`, `aborts`,
`unaffected`, `rtb`, and `interceptions` as the compatibility total `kills + aborts`). The single
ledger is `manpads_intercept_log`.

Draw-order note: the engagement sits inside the post-AD strike phase, on the day's retained
air-engagement substream, immediately after the same package's SAM ingress fire and before its
strike rolls. Tests: `tests/ijfs/ijfs_manpads_test.gd` and
`tests/ijfs/ijfs_package_ingress_test.gd`; data guards in `tools/validate_ijfs_data.gd` (50 bins /
2,500 launchers / category exclusions).

Calibration levers: the fitted `manpads_attrition_factor` scenario knob (kill), plus the constants
`SATURATION_SYSTEMS`, `ABORT_FACTOR` and `EXPEND_PER_ENGAGEMENT` in `IjfsManpads.gd`. The abort
factor is deliberately NOT a scenario knob: being driven off is a property of the launcher's
presence, not something the fit needs to move. Measured magnitudes and the calibration closure are
in `docs/archive/0060-air-attrition-before-the-strike.md`.
