class_name IjfsEngine
extends RefCounted

## Port of ijfs_standalone/run_daily_ijfs.py (the 6-phase daily orchestration) + run_context.py
## (day-semantics). Deliberately does NOT port write_outputs file IO: run_daily returns the ledgers
## dict directly (detection / strike / engagement / contest / free-shot / target-status / inventory /
## OOB / summary).
##
## This file is the ORDER of a day and nothing else. Two halves moved out on 2026-08-01 (plan 0060) —
## IjfsStrikePhase owns each strike pass, IjfsLedgers owns the summary and the record — which both
## reads better and pays for the collaborators plan 0060 adds, since the engine was already at its
## dependency ceiling and that ceiling is paid, never raised.
##
## RNG fidelity: a single shared `dice: Dice` is threaded into every probabilistic phase, exactly
## mirroring the Python single `state.rng`. Draw order across phases:
##   1. (warmup only) exquisite-intel auto-detect rolls
##   2. satellite (phase1) detection
##   3. pre-AD strike phase (resolve_strike per attacked target)
##   4. SEAD engagement + return-fire
##   5. aircraft (phase2) detection
##   6. post-AD strike phase
##   7. post-phase-2 free shot
##
## Continuity: targets/munitions/squadron_force live on the state and persist across days; call
## carry_to_next_day(state) between days to reproduce the loader's reload reset (clear suppression
## + sead_result; destroyed / known_to_red / inventory / squadron attrition carry forward).

const PRE_AD_PHASE := "pre_ad_recompute"
const POST_AD_PHASE := "post_ad_recompute"

# Exquisite-intel config key -> runtime IjfsTarget.category it overrides (insertion order matters
# for RNG draw order; mirrors run_daily_ijfs.EXQUISITE_INTEL_CATEGORIES).
const EXQUISITE_INTEL_CATEGORIES := [
	["maneuver", "Maneuver Units"],
	["antiship", "Anti-Ship Systems"],
]

# Every key the engine reads out of warmup_context, via wc.get(...). The producer
# (IjfsResolver.build_warmup_context) must emit only these; an unrecognized key means a typo that would
# otherwise silently go dead (the class of bug that left exquisite intel dormant). Guarded in run_daily.
const WARMUP_CONTEXT_KEYS := {
	"x_day": true, "z_day": true, "sead_enabled": true, "ad_attrition_enabled": true,
	"munition_filter": true, "posture_default_override": true, "release_rules": true,
	"firing_capacity_config": true, "exquisite_intel": true,
}


# --- Run context (port of run_context.IJFSRunContext.from_run_args) -------------------------------

static func make_run_context(current_day: int, warmup_context: Variant) -> Dictionary:
	if warmup_context == null:
		return {
			"current_day": current_day,
			"isr_day": current_day if current_day >= 1 else 1,
			"z_day": null,
			"x_day": null,
			"is_warmup": false,
		}
	var wc: Dictionary = warmup_context
	return {
		"current_day": current_day,
		"isr_day": int(wc.get("x_day", 1)),
		"z_day": wc.get("z_day", 0),
		"x_day": int(wc.get("x_day", 1)),
		"is_warmup": true,
	}


## Returns warmup_context keys not in WARMUP_CONTEXT_KEYS — i.e. typos the engine would silently ignore.
## Empty == healthy. run_daily asserts this is empty; also unit-testable without tripping the assert.
static func unknown_warmup_keys(wc: Dictionary) -> Array:
	var unknown: Array = []
	for key in wc.keys():
		if not WARMUP_CONTEXT_KEYS.has(key):
			unknown.append(key)
	unknown.sort()
	return unknown


# --- Daily orchestration (port of run_daily_ijfs, minus path loading + write_outputs) -------------

static func run_daily(state: IjfsDailyState, dice: Dice, current_day: int, warmup_context: Variant = null) -> Dictionary:
	state.detection_log = []
	state.strike_log = []
	state.engagement_log = []
	state.contest_log = []
	state.free_shot_log = []
	state.manpads_intercept_log = []
	state.exquisite_intel_overrides = []

	var run_ctx := make_run_context(current_day, warmup_context)
	var air_classes: Variant = state.air_classes
	var air_classes_dict: Dictionary = air_classes if air_classes is Dictionary else {}
	var squadron_force: Variant = state.squadron_force

	# One bundle threaded through both strike passes; `attacked` / `skip_reasons` accumulate across
	# them, and `organic_budget` is filled in between (see IjfsStrikePhaseContext).
	var ctx := IjfsStrikePhaseContext.new()
	ctx.current_day = int(run_ctx["current_day"])
	ctx.z_day = run_ctx["z_day"]
	# One shared survivability profile per day: RCS signature x role exposure, read by every path
	# that can kill an aircraft so none of them re-derives a modifier (plan 0060 R2).
	ctx.attrition = IjfsAttritionProfile.build(state.scenario, air_classes)
	# One RETAINED child stream for every air-engagement roll of the day (plan 0060). Deriving it per
	# package would hand each package the same sequence; deriving it here keeps package geometry from
	# shifting the strike, detection and SEAD draws it sits between.
	ctx.air_engagement_dice = dice.derive("ijfs_air_engagements")

	if warmup_context != null:
		var wc: Dictionary = warmup_context
		var unknown_keys := unknown_warmup_keys(wc)
		assert(unknown_keys.is_empty(), "Unknown warmup_context key(s): %s — typo? Known keys: %s" % [", ".join(unknown_keys), ", ".join(WARMUP_CONTEXT_KEYS.keys())])
		IjfsTargeting.apply_posture_override(state.targets, wc.get("posture_default_override"))
		var exquisite: Dictionary = wc.get("exquisite_intel", {})
		var x_day := int(wc.get("x_day", 1))
		for pair in EXQUISITE_INTEL_CATEGORIES:
			var config_key: String = pair[0]
			var target_category: String = pair[1]
			var overrides := IjfsTargeting.apply_exquisite_intel(state.targets, exquisite, x_day, dice, config_key, target_category)
			state.exquisite_intel_overrides.append_array(overrides)
		var firing_cfg: Dictionary = wc.get("firing_capacity_config", {})
		if not firing_cfg.is_empty():
			ctx.capacity_budget = IjfsFiringCapacity.FiringCapacityBudget.new(firing_cfg, state.munitions)
		var wc_release: Array = wc.get("release_rules", [])
		ctx.release_rules = wc_release if not wc_release.is_empty() else null
		var wc_filter: Dictionary = wc.get("munition_filter", {})
		ctx.munition_filter = wc_filter if not wc_filter.is_empty() else null
	else:
		ctx.capacity_budget = IjfsFiringCapacity.FiringCapacityBudget.new(state.scenario.get("red_firing_capacity", {}), state.munitions)

	state.taiwan_ad_health_before = IjfsAdHealth.compute_taiwan_ad_health(state.targets, state.scenario)

	var phase1 := IjfsDetection.satellite_detect_target_ids(state.targets, state.scenario, dice)
	state.detection_log = phase1["log"]
	IjfsDetection.apply_detection_ids(state.targets, phase1["detected_ids"], ctx.current_day)

	IjfsStrikePhase.run(state, ctx, PRE_AD_PHASE, dice)

	state.taiwan_ad_health_after_missile_phase = IjfsAdHealth.compute_taiwan_ad_health(state.targets, state.scenario)

	var sead_enabled := warmup_context == null or bool((warmup_context as Dictionary).get("sead_enabled", true))
	var ad_attrition_enabled := warmup_context == null or bool((warmup_context as Dictionary).get("ad_attrition_enabled", true))
	ctx.ad_attrition_enabled = ad_attrition_enabled

	var engagement := IjfsEngagement.resolve_sead_engagement(state.targets, squadron_force, ctx.attrition, dice, sead_enabled, ad_attrition_enabled)
	state.engagement_log = engagement["engagement_log"]
	state.contest_log = engagement["contest_log"]

	state.taiwan_ad_health_after_sead = IjfsAdHealth.compute_taiwan_ad_health(state.targets, state.scenario)

	# Organic strike capacity depends on the aircraft that survived SEAD, so it is only known here —
	# which is why the pre-AD pass ran with it still null.
	if squadron_force != null:
		ctx.organic_budget = IjfsFiringCapacity.OrganicStrikeBudget.new(state.scenario, squadron_force, state.munitions, air_classes)

	var phase2 := IjfsDetection.aircraft_detect_target_ids(state.targets, state.scenario, squadron_force, air_classes_dict, 1.0, dice, int(run_ctx["isr_day"]))
	state.detection_log.append_array(phase2["log"])
	IjfsDetection.apply_detection_ids(state.targets, phase2["detected_ids"], ctx.current_day)

	IjfsStrikePhase.run(state, ctx, POST_AD_PHASE, dice)
	IjfsStrikePhase.append_final_skips(state, ctx)

	state.taiwan_ad_health_after = IjfsAdHealth.compute_taiwan_ad_health(state.targets, state.scenario)

	state.free_shot_log = IjfsEngagement.apply_post_phase_2_free_shot(
		squadron_force,
		ctx.attrition,
		float(state.taiwan_ad_health_after.get("raw_sam_health", 0.0)),
		dice,
		ad_attrition_enabled,
	)

	var summary := IjfsLedgers.summarize_run(state)
	if ctx.capacity_budget != null:
		summary["firing_capacity_utilization"] = ctx.capacity_budget.utilization()

	return IjfsLedgers.build_ledgers(state, current_day, summary)


# --- Continuity (in-memory equivalent of the loader reload reset) -------------------------------

static func carry_to_next_day(state: IjfsDailyState) -> void:
	# Mirrors loaders.load_targets's runtime-reload branch: suppression + sead_result clear each
	# day; destroyed / known_to_red / last_detected_day / detected_this_turn persist. Munitions and
	# squadron_force carry forward unchanged (their attrition is already applied in-place).
	IjfsTransitions.carry_to_next_day(state)
