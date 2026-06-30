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
| `scripts/GameState.gd` | Warmup driver (`_build_warmup_context`), `resolve_ijfs_turn`, `_compute_ijfs_writeback` | TIV warmup driver + write-outputs aggregation |

## 3. Daily Pipeline — Stage Order in `IjfsEngine.run_daily`

Mirrors `run_daily_ijfs.py` lines 95–218. Each stage consumes the shared `Dice` in sequence:

1. **Warmup setup** (if warmup_context): posture override → exquisite-intel auto-detects → firing
   capacity scaling + release rules + munition filter (IjfsEngine.gd:74–90)
2. **AD health snapshot 1** (`taiwan_ad_health_before`; IjfsEngine.gd:94)
3. **Satellite detection (phase 1)**: static/intel-locked targets auto-detected; other targets roll
   vs satellite-floor probability (IjfsEngine.gd:96–98)
4. **Pre-AD strike phase**: iterate `targets_to_attack`, select munition via doctrine, resolve
   strike, consume firing capacity (IjfsEngine.gd:100–102)
5. **AD health snapshot 2** (`taiwan_ad_health_after_missile_phase`; IjfsEngine.gd:104)
6. **SEAD engagement**: resolve SAM destruction/suppression + return-fire contest
   (IjfsEngine.gd:109–111)
7. **AD health snapshot 3** (`taiwan_ad_health_after_sead`; IjfsEngine.gd:113)
8. **Aircraft detection (phase 2)**: ISR score = non-air sources + alive ISR aircraft ISR value /
   reference, clamped (IjfsEngine.gd:119–121)
9. **Post-AD strike phase**: repeat targeting with organic (strike-aircraft) budget added
   (IjfsEngine.gd:123)
10. **Append final skips**: targets not attacked get a skip-log entry (IjfsEngine.gd:124)
11. **AD health snapshot 4** (`taiwan_ad_health_after`; IjfsEngine.gd:126)
12. **Free shot**: remaining SAM health inflicts post-phase-2 attrition
    (IjfsEngine.gd:128–134)
13. **Summarize + build ledgers** (IjfsEngine.gd:136–140)

## 4. Detection / Targeting / Engagement / Strike — Key Formulas

### Detection (`IjfsDetection.gd`)

- **ISR source capability**: `floor + (initial - floor) * exp(-d * ln2 / half_life)` (exp_decay);
  also supports linear, weibull, logistic, gompertz, from_attrition, piecewise
  (IjfsDetection.gd:22–57)
- **Satellite detection (phase 1)**: `p_detect = clamp(satellite_floor[mobility][posture])` — no ISR
  score contribution (IjfsDetection.gd:142)
- **Aircraft detection (phase 2)**: `p_detect = clamp(satellite_floor + base_prob * mobility_mult *
  posture_mult * weighted_isr)` where `weighted_isr = max(0, (non_air_score + aircraft_score) *
  contest_adjustment)` (IjfsDetection.gd:168–171)
- **Aircraft ISR raw**: `sum(alive * isr_value_per_aircraft) / reference_isr_sum` for ISR-role
  squadrons (IjfsDetection.gd:77–91)
- Static targets and `intel_locked` targets bypass rolls (auto-detected).
- **Green maneuver units (D4-H)**: `IjfsLoaders.build_maneuver_targets` emits one "Maneuver Units"
  target per ROC battalion instance; its `(mobility, hardness, detectability_active/hiding)` come from
  the `MANEUVER_TYPE_MAP` profile (less-mobile/softer → more findable/lethal). `posture` is set each
  turn by `GameState._update_maneuver_posture`: a brigade that moved or fought last turn (the
  `moved_last_turn`/`fought_last_turn` flags) presents `posture="active"` — selecting the higher
  `detectability_active` label plus the active posture/satellite multipliers above — otherwise `"hiding"`.

### Targeting (`IjfsTargeting.gd`)

- `targets_to_attack`: not destroyed AND detected_this_turn AND (if z_day/release_rules) release
  day met (IjfsTargeting.gd:8–17)
- Pairing match: by source_target_id or (category, subcategory*, mobility*, hardness*) wildcard
  match (IjfsTargeting.gd:20–31)
- Doctrine priority: `match_doctrine_rule` matched on category/subcategory/mobility/hardness →
  munition_priority list → fallback to compatibility order (IjfsTargeting.gd:128–159)
- Exquisite intel: config-driven `initial_count * decay fraction` targets randomly selected (or
  deterministically) and `intel_locked = true` (IjfsTargeting.gd:227–266)

### Engagement / SEAD (`IjfsEngagement.gd`)

- **SEAD power**: `total_sead_eff * (1 + avg_wvr * 0.1) * (1 - avg_rcs * 0.05)`
  (IjfsEngagement.gd:59–61)
- **SAM destroy**: `p_destroy = clamp(effective_power / (effective_power + sam_score), 0, 1)`
  (IjfsEngagement.gd:67)
- **SAM suppress** (if not destroyed): `p_suppress = p_destroy * 0.4` (IjfsEngagement.gd:80)
- **Return fire**: `loss_rate = clamp(surviving_sam_score * 0.02, 0, 1)` per squadron with RCS
  survival mod `max(0.2, 1 + rcs * 0.1)` (IjfsEngagement.gd:109–116)
- **Free shot** (post-phase-2): `loss_rate = clamp(raw_sam_health * 0.05, 0, 1)` with same RCS
  survival mod (IjfsEngagement.gd:145, 151–152)

### Strike (`IjfsStrike.gd`)

- **Probability model**: `final = clamp((base + add_sum) * mult_product)` from
  `strike_probability_modifiers` in scenario config (IjfsStrike.gd:87). Falls back to legacy
  mobile-target cap system (IjfsStrike.gd:208–223)
- **Suppression** (if not destroyed): roll `probability_suppressed_if_not_destroyed` from pairing
  (IjfsStrike.gd:140–153)
- Data tables used: `pairings.json` (base probabilities per munition-target pair),
  `scenario.json` (`strike_probability_modifiers`, `mobile_target_destroy_caps`)

## 5. Warmup — Multi-Day Capability Ramp

The warmup runs before D-Day in `GameState.resolve_ijfs_turn` when `_ijfs_day == 0`
(scripts/GameState.gd:423–448). Over `prelanding.days` (typically 4, via
`PRE_INVASION_IJFS_DAYS`):

- Each day `i` (1-indexed) calls `_build_warmup_context` (GameState.gd:467–486) which:
  - Computes `profile_multiplier` via `IjfsWarmup` (even/front_loaded/back_loaded):
    `(2 * weight) / (total_days + 1)` where weight = total_days - x_day + 1 (front) or x_day (back)
    (IjfsWarmup.gd:15–21)
  - Scales `red_firing_capacity` sorties per day by multiplier (IjfsWarmup.gd:24–32)
  - Applies `posture_default_override`, `sead_enabled`, `ad_attrition_enabled`, `munition_filter`
    from scenario `prelanding.rules`
- Exquisite intel on day 1 (x_day) auto-detects a configurable count of Maneuver Units and
  Anti-Ship Systems, marking them `intel_locked` for that day. Decay reduces that count over
  subsequent warmup days (IjfsTargeting.gd:227–266).
- A fresh `SeededDice` substream per warmup day preserves reproducibility
  (GameState.gd:440–444).
- Post-warmup turns run one plain `run_daily` call with `warmup_context = null`.

## 6. AD Health / Suppression

`IjfsAdHealth.compute_taiwan_ad_health` (IjfsAdHealth.gd:12–34) computes:

- **Category health** per AD type: `alive_unsuppressed / total` for each of Moveable SAMs, Static
  SAMs, Static Radars, Mobile Radars
- **Weighted averages**: `raw_sam_health` over SAM categories, `radar_health` over radar categories
- **Effective AD health**: `clamp(sam_weight_total * (raw_sam_health * radar_health) +
  radar_weight_total * radar_health, 0, 1)`

Snapshot before engagement: used by the pre-AD strike phase. Snapshot after missile phase: used by
SEAD return-fire. Snapshot after SEAD: used by post-AD strike. Final snapshot: used by free shot.

**Impact on D3 (anti-ship)**: suppressed Green systems are excluded from the AD health calculation.
`_compute_ijfs_writeback` (GameState.gd:519–579) reads cumulative `target.suppressed` from
`ijfs_state.targets` for each "Anti-Ship Systems" category target, producing
`antiship_suppressed_by_type` by (TO,type) key. `resolve_antiship_turn` (GameState.gd:587–669)
uses these to reduce `system.quantity` and `fire_pct`.

## 7. Writeback — Per-(TO,type) Outputs

`_compute_ijfs_writeback` (GameState.gd:519–579) aggregates:

| Ledger key | Source | Consumers |
|---|---|---|
| `antiship_destroyed_by_type` | Cumulative `target.destroyed` on Anti-Ship Systems targets | D3 `resolve_antiship_turn`: reduces system quantity (GameState.gd:645–646) |
| `antiship_suppressed_by_type` | Cumulative `target.suppressed` on Anti-Ship Systems targets | D3 `resolve_antiship_turn`: reduces fire percentage proportional to suppressed/available (GameState.gd:653–654) |
| `maneuver_casualties` | Strike log entries for "Maneuver Units" with `destroyed = true` (carry `brigade_id`/`battalion_id`/`unit_type` from target metadata) | **CLOSED (D4-H)** — `GameState._apply_ijfs_maneuver_casualties` decrements the struck battalions' `qty` in the OOB before ground combat |
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
| **Orchestrator** | `IjfsEngine.gd` | `run_daily_ijfs.py` | **1:1** — identical 6-phase pipeline, same draw order comment block (IjfsEngine.gd:12–17). Replaces file `write_outputs` with in-memory `_build_ledgers` returning dict. `summarize_run` is explicit (not delegated to logging_utils). `EXQUISITE_INTEL_CATEGORIES` changed from dict to Array of pairs to preserve insertion order (RNG draw-order guarantee). |
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
| **Warmup driver** | `GameState.gd:resolve_ijfs_turn` | TIV warmup driver (standalone) | **1:1** — multi-day loop, `carry_to_next_day` between days, SeededDice substream per day. |
| **Writeback** | `GameState.gd:_compute_ijfs_writeback` | TIV `write_outputs` aggregation | **1:1** — anti-ship writeback reads cumulative target state (not per-day delta), keyed by (TO,type). |

### Open Questions

1. **✅ Maneuver-casualties linkage CLOSED 2026-06-29 (overnight 2b–2d).** Green/ROC maneuver battalions
   are now generated as IJFS targets (`IjfsLoaders.build_maneuver_targets`, wired in
   `_rebuild_ijfs_state`), struck, written back (`maneuver_casualties` populates), and **consumed**
   (`GameState._apply_ijfs_maneuver_casualties` removes struck battalions from the OOB before ground
   combat). Tests: `ijfs_maneuver_targets_test.gd`, `ijfs_maneuver_consume_test.gd`. The 2c-ii
   detection/lethality bias is the remaining refinement. _Historical (now resolved) description:_
   (a) **No ID bridge** — `maneuver_casualties` is accumulated in `_compute_ijfs_writeback`
   (`GameState.gd:547–563`, a faithful port of `ijfs_maneuver_writeback_service`), but at runtime it is
   **empty** because IJFS maneuver targets carry no `battalion_id`/`brigade_id` matching the PLA/ROC OOB.
   (b) **No consumer** — even when populated, nothing applies it: only `antiship_destroyed_by_type` is
   consumed (`GameState.gd:624`, feeds the D3 firing plan); `maneuver_casualties` is merely exposed in
   the LLM observation (`LLMGameAPI.gd:252`). So IJFS air/missile kills do **not** reduce the brigades
   that fight in ground combat. (See `docs/plans/port_audit.md` — "Ground-casualty IJFS↔OOB linkage",
   status ADAPT; design settled 2026-06-28.)

2. **Squadron force shape**: HexCombat passes `Array[IjfsSquadron]` directly where TIV wraps it in
   a `SquadronForce` dataclass with a `.squadrons` attribute. All call sites handle both
   (`_force_squadrons` in IjfsDetection.gd:237–246), but the dual-path is a divergence surface.

3. **Category groups**: `category_groups.py` (operational_chart_categories,
   static_chart_categories) is not ported — these are chart-filtering constants only, not part of
   the simulation pipeline. Port if a reporting view needs them.
