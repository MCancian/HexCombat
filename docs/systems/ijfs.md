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
| `scripts/ijfs/IjfsEngine.gd` | Daily orchestration (6-phase pipeline), run context, ledgers, continuity | `run_daily_ijfs.py`, `run_context.py`, `logging_utils.py` |
| `scripts/ijfs/IjfsDetection.gd` | Satellite (phase1) + aircraft (phase2) ISR detection | `detection.py`, `isr_sources.py`, `antiship_exposure.py`, `math_utils.py` |
| `scripts/ijfs/IjfsTargeting.gd` | Target filtering, pairing matching, doctrine priority, munition filter, exquisite intel | `targeting.py` |
| `scripts/ijfs/IjfsEngagement.gd` | SEAD engagement + return-fire (contest) + post-phase-2 free shot | `engagement.py` |
| `scripts/ijfs/IjfsStrike.gd` | Strike probability (modifier system + legacy mobile-cap fallback) and hit resolution | `strike_probability.py`, `strike_resolution.py` |
| `scripts/ijfs/IjfsFiringCapacity.gd` | `FiringCapacityBudget` (inorganic daily sortie cap) + `OrganicStrikeBudget` (strike-aircraft scaled) | `firing_capacity.py` |
| `scripts/ijfs/IjfsAdHealth.gd` | Taiwan AD health: per-category alive+unsuppressed fraction, SAM×radar effective health | `ad_health.py` |
| `scripts/ijfs/IjfsWarmup.gd` | Prelanding attrition-profile multiplier + capacity scaling | `warmup_profiles.py` |
| `scripts/ijfs/IjfsDailyState.gd` | Mutable container threaded through one daily cycle | `state.py` (IJFSDailyState, minus rng) |
| `scripts/ijfs/IjfsLoaders.gd` | JSON loading, target expansion, anti-ship container→target builder, SAM score enrichment | `loaders.py` + `default_targets.py` |
| `scripts/model/ijfs/IjfsTarget.gd` | Resource model: target state fields + `to_dict()` | `state.py` (TargetInstance dataclass) |
| `scripts/model/ijfs/IjfsMunition.gd` | Resource model: munition inventory row | `state.py` (MunitionInventory dataclass) |
| `scripts/model/ijfs/IjfsPairing.gd` | Resource model: munition-target effect pairing | `state.py` (PairingRule dataclass) |
| `scripts/model/ijfs/IjfsSquadron.gd` | Resource model: squadron state (class, role, alive, losses) | `state.py` (SquadronState dataclass) |
| `scripts/resolvers/IjfsResolver.gd` | Pure resolver (Phase C): `resolve()` orchestrates the daily pipeline call (warmup loop or single plain day), `build_warmup_context()`, `compute_writeback()`, maneuver-target sync/posture/consume. Read its header for the purity boundary with `GameState`. | TIV warmup driver + write-outputs aggregation |
| `scripts/GameState.gd` | Thin wrapper: `resolve_ijfs_turn()` lazily builds `ijfs_state` then delegates to `IjfsResolver.resolve()`; `_build_warmup_context()` delegates to `IjfsResolver.build_warmup_context()`. Owns the `EventBus.ijfs_resolved` emit and cross-turn field writes (`_ijfs_day`, `last_ijfs_summary`, `last_ijfs_writeback`). | — |

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
6. **SEAD engagement**: resolve SAM destruction/suppression + return-fire contest
7. **AD health snapshot 3** (`taiwan_ad_health_after_sead`)
8. **Aircraft detection (phase 2)**: ISR score = non-air sources + alive ISR aircraft ISR value /
   reference, clamped
9. **Post-AD strike phase**: repeat targeting with organic (strike-aircraft) budget added
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
  turn by `IjfsResolver.update_maneuver_posture` (called via `GameState._update_maneuver_posture`):
  a brigade that moved or fought last turn (the `moved_last_turn`/`fought_last_turn` flags) presents
  `posture="active"` — selecting the higher `detectability_active` label plus the active
  posture/satellite multipliers above — otherwise `"hiding"`. Because `ijfs_state` is built once
  per scenario, `IjfsResolver.sync_maneuver_targets_to_oob` (called via
  `GameState._sync_maneuver_targets_to_oob`) also runs each turn to mark `destroyed` the maneuver
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

- **SEAD power**: `total_sead_eff * (1 + avg_wvr * 0.1) * (1 - avg_rcs * 0.05)`
- **SAM destroy**: `p_destroy = clamp(effective_power / (effective_power + sam_score), 0, 1)`
- **SAM suppress** (if not destroyed): `p_suppress = p_destroy * 0.4`
- **Return fire**: `loss_rate = clamp(surviving_sam_score * 0.02, 0, 1)` per squadron with RCS
  survival mod `max(0.2, 1 + rcs * 0.1)`
- **Free shot** (post-phase-2): `loss_rate = clamp(raw_sam_health * 0.05, 0, 1)` with same RCS
  survival mod

### Strike (`IjfsStrike.gd`)

- **Probability model**: `final = clamp((base + add_sum) * mult_product)` from
  `strike_probability_modifiers` in scenario config. Falls back to legacy mobile-target cap system.
- **Suppression** (if not destroyed): roll `probability_suppressed_if_not_destroyed` from pairing
- Data tables used: `pairings.json` (base probabilities per munition-target pair),
  `scenario.json` (`strike_probability_modifiers`, `mobile_target_destroy_caps`)
- **Calibration knob** (plan 0001, crossing-lethality, USER dial-in 2026-07-11):
  `scenario.intel_locked_antiship_strike_bonus` (float; golden = 0.20) is a scalar add-bonus to
  strike probability against exquisite-intel-locked anti-ship coastal launchers (category
  `Anti-Ship Systems`, `intel_locked: true`). `IjfsLoaders.apply_intel_locked_strike_bonus`
  synthesizes it into a `strike_probability_modifiers` entry
  (`modifier_id: intel_locked_antiship_precision_strike`) at scenario-load time, so authors set one
  number instead of hand-writing the modifier's match/operation shape; 0.0 is a no-op. Paired with
  the companion lever `prelanding.intel.exquisite_intel.antiship.initial_count` (golden = 36), a
  plain data field read directly by `IjfsTargeting.apply_exquisite_intel` — no code promotion
  needed, editing the JSON value is sufficient. Together these hit the USER's ~25% mean crossing-loss
  target (N=30-seed sweep). Sweep tool: `tools/sweep_antiship_crossing.gd`, mutates both in-memory
  to grid-search without rewriting the file.

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
(TO,type) key. `AntishipResolver.resolve` (called by `GameState.resolve_antiship_turn`) applies
these to reduce `system.quantity` and `fire_pct`.

## 7. Writeback — Per-(TO,type) Outputs

`IjfsResolver.compute_writeback` aggregates:

| Ledger key | Source | Consumers |
|---|---|---|
| `antiship_destroyed_by_type` | Cumulative `target.destroyed` on Anti-Ship Systems targets | D3 `AntishipResolver.resolve`: reduces system quantity |
| `antiship_suppressed_by_type` | Cumulative `target.suppressed` on Anti-Ship Systems targets | D3 `AntishipResolver.resolve`: reduces fire percentage proportional to suppressed/available |
| `maneuver_casualties` | Strike log entries for "Maneuver Units" with `destroyed = true` (carry `brigade_id`/`battalion_id`/`unit_type` from target metadata) | **CLOSED (D4-H)** — `IjfsResolver.apply_maneuver_casualties` (called by `GameState._apply_ijfs_maneuver_casualties`) decrements the struck battalions' `qty` in the OOB before ground combat |
| `sam_destroyed` / `sam_suppressed` | Engagement log SEAD outcomes | Summary only |

Anti-ship writeback keys use `AntishipCalculator.encode_key(to_number, type_id)` —
container-level targets carry `systems_represented` in metadata, so destroying one bin removes its
whole count from the firing plan.

## 8. Data Files

| File | Schema (first 20 lines) | Lines | Used by |
|---|---|---|---|
| `data/ijfs/targets_master.json` | Top-level `metadata` + `targets[]` array of target rows with `target_id, category, subcategory, quantity, mobility, detectability_*` | 2489 | `IjfsLoaders.load_targets` |
| `data/ijfs/red_munitions.json` | `metadata` + `munitions[]` with `munition_id, category, inventory_remaining_default, rounds_per_engagement_default` | 453 | `IjfsLoaders.load_munitions` |
| `data/ijfs/munition_target_pairings.json` | `metadata, target_effect_profiles[], pairings[]` — 52 profiles, 8 munitions, 333 pairings with `probability_destroyed, rounds_expended_per_engagement` | 10183 | `IjfsLoaders.load_pairings` |
| `data/ijfs/ijfs_scenario.json` | `schema_version: 1, china_isr_pools, detection_model, taiwan_air_defense_health, prelanding, red_firing_capacity, isr_sources, target_release, strike_probability_modifiers, mobile_target_destroy_caps, targeting_doctrine` | 615 | `IjfsLoaders.load_scenario` |
| `data/ijfs/red_air_oob.json` | `model_version, red_air_oob[]` — 11 rows with class/role/squadrons/aircraft_per_sqn | 16 | `IjfsLoaders.load_oob` |
| `data/ijfs/air_classes.json` | `model_version, reference_isr_sum, classes{}` — 11 classes with `kind, rcs, wvr, isr_value, sead_eff` | 17 | `IjfsLoaders.load_air_classes` |
| `data/ijfs/sam_capabilities.json` | `model_version, fallback_by_category, sam_score_by_subcategory` | 17 | `IjfsLoaders.load_sam_capabilities` |
| `data/ijfs/grouped_targets.json` | `metadata, groups[]` — mobile SAM relocation grouping | 104 | Used by validation scripts |

## 9. TIV-Port Fidelity Notes

| Stage | HexCombat file | TIV file | Fidelity |
|---|---|---|---|
| **Orchestrator** | `IjfsEngine.gd` | `run_daily_ijfs.py` | **1:1** — identical 6-phase pipeline, same draw-order comment block at the top of the file. Replaces file `write_outputs` with in-memory `_build_ledgers` returning dict. `summarize_run` is explicit (not delegated to logging_utils). `EXQUISITE_INTEL_CATEGORIES` changed from dict to Array of pairs to preserve insertion order (RNG draw-order guarantee). |
| **Run context** | `IjfsEngine.make_run_context` | `run_context.IJFSRunContext.from_run_args` | **1:1** — same field logic (current_day, isr_day, z_day, x_day, is_warmup). |
| **Detection** | `IjfsDetection.gd` | `detection.py` + `isr_sources.py` | **1:1** — every `evaluate_isr_source` curve mode (exp_decay, linear, weibull, logistic, gompertz, from_attrition, piecewise) matches; `_apply_antiship_exposure_modifier` inlined rather than importing from `antiship_exposure.py`. |
| **Targeting** | `IjfsTargeting.gd` | `targeting.py` | **1:1** — `targets_to_attack`, `pairing_matches_target`, `select_munition_with_doctrine`, doctrine matching, `apply_exquisite_intel` all match signature-for-signature. |
| **Engagement** | `IjfsEngagement.gd` | `engagement.py` | **1:1** — constants, SEAD power formula, p_destroy, suppression factor, return-fire, free shot all identical. Returns dict instead of tuple. |
| **Strike Pk** | `IjfsStrike.gd` | `strike_probability.py` | **1:1** — modifier matching, `probability_context`, `evaluate_strike_probability`, `_legacy_cap_probability` all match. |
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
   `_rebuild_ijfs_state`), struck, written back (`maneuver_casualties` populates), and **consumed**
   (`GameState._apply_ijfs_maneuver_casualties` removes struck battalions from the OOB before ground
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
shoulder launchers. Instead (`scripts/ijfs/IjfsManpads.gd`, wired in `IjfsEngine.run_daily`):

1. **Strike interception** — each about-to-execute strike whose munition has
   `manpads_vulnerability > 0` (`red_munitions.json`: attack UAV 1.0, OWA drone 1.0, strike
   aircraft 0.4; ballistic/cruise 0 — they fly above MANPADS) rolls interception against the
   ready launchers in the TARGET's TO before its own strike rolls: `p = threat × 0.15 × vuln`,
   `threat = clamp(ready/500)` (saturating — coverage, not headcount). An intercepted strike
   spends its round and delivers nothing (`intercepted_by_manpads` in the strike log).
2. **Squadron contest** — SEAD + strike squadrons (ISR flies high) take island-wide per-aircraft
   bernoulli losses after the post-AD strike phase (`p = threat × 0.01 × rcs_survival`), folded
   into `red_air_losses` (`source: "manpads"` in `manpads_contest_log`); gated by
   `ad_attrition_enabled` like the SAM layers.
3. **Deterioration** — three drains: usage (3 missiles per interception attempt, 1 per contested
   aircraft, lowest `target_id` bins first), bombardment (bins stay strikeable through the normal
   pairing path — 6 pairings retargeted to category `MANPADS`), and ground losses
   (`IjfsResolver.sync_manpads_to_oob`: each TO's pool is capped at
   `systems_represented × alive/total` of that TO's Maneuver-Unit targets — MANPADS ride with the
   infantry; zero dice, idempotent, monotonic).

Summary surface: `ijfs_summary.manpads` (`ready_systems_by_to`, `interception_attempts`,
`interceptions`, `squadron_losses`); ledgers export `manpads_intercept_log`/`manpads_contest_log`.
Draw-order note: interception draws sit inside the strike phases; the contest sits between the
post-AD strike phase and the free shot — re-baselining pins was part of landing this
(validate_cleanup fingerprint, validate_golden_victory census, llm_result fixture).
Tests: `tests/ijfs/ijfs_manpads_test.gd`; data guards in `tools/validate_ijfs_data.gd`
(50 bins / 2,500 launchers / category exclusions). Calibration levers (constants in
`IjfsManpads.gd`): `SATURATION_SYSTEMS`, `INTERCEPT_FACTOR`, `SQUADRON_LOSS_FACTOR`,
`EXPEND_PER_INTERCEPT`, `EXPEND_PER_CONTEST_AIRCRAFT` — observed magnitudes on the golden seed:
~5–9 Red aircraft lost/turn at full threat, pools 2,500→~460 by turn 4.
