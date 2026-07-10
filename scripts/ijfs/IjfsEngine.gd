class_name IjfsEngine
extends RefCounted

## Port of ijfs_standalone/run_daily_ijfs.py (the 6-phase daily orchestration) + run_context.py
## (day-semantics) + logging_utils.summarize_run. Deliberately does NOT port write_outputs file
## IO: run_daily returns the ledgers dict directly (detection / strike / engagement / contest /
## free-shot / target-status / inventory / OOB / summary).
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
# (GameState._build_warmup_context) must emit only these; an unrecognized key means a typo that would
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
	state.manpads_contest_log = []
	state.exquisite_intel_overrides = []

	var ctx := make_run_context(current_day, warmup_context)
	var air_classes: Variant = state.air_classes
	var air_classes_dict: Dictionary = air_classes if air_classes is Dictionary else {}
	var squadron_force: Variant = state.squadron_force

	var capacity_budget: Variant = null
	var release_rules: Variant = null
	var munition_filter: Variant = null

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
			capacity_budget = IjfsFiringCapacity.FiringCapacityBudget.new(firing_cfg, state.munitions)
		var wc_release: Array = wc.get("release_rules", [])
		release_rules = wc_release if not wc_release.is_empty() else null
		var wc_filter: Dictionary = wc.get("munition_filter", {})
		munition_filter = wc_filter if not wc_filter.is_empty() else null
	else:
		capacity_budget = IjfsFiringCapacity.FiringCapacityBudget.new(state.scenario.get("red_firing_capacity", {}), state.munitions)

	state.taiwan_ad_health_before = IjfsAdHealth.compute_taiwan_ad_health(state.targets, state.scenario)

	var phase1 := IjfsDetection.satellite_detect_target_ids(state.targets, state.scenario, dice)
	state.detection_log = phase1["log"]
	IjfsDetection.apply_detection_ids(state.targets, phase1["detected_ids"], ctx["current_day"])

	var attacked: Dictionary = {}        # target_id -> true (set)
	var skip_reasons: Dictionary = {}    # target_id -> [reason, doctrine_name, doctrine_selection]
	_run_strike_phase(state, ctx["current_day"], PRE_AD_PHASE, attacked, skip_reasons, dice, capacity_budget, null, ctx["z_day"], release_rules, munition_filter)

	state.taiwan_ad_health_after_missile_phase = IjfsAdHealth.compute_taiwan_ad_health(state.targets, state.scenario)

	var sead_enabled := warmup_context == null or bool((warmup_context as Dictionary).get("sead_enabled", true))
	var ad_attrition_enabled := warmup_context == null or bool((warmup_context as Dictionary).get("ad_attrition_enabled", true))

	var engagement := IjfsEngagement.resolve_sead_engagement(state.targets, squadron_force, air_classes, dice, sead_enabled, ad_attrition_enabled)
	state.engagement_log = engagement["engagement_log"]
	state.contest_log = engagement["contest_log"]

	state.taiwan_ad_health_after_sead = IjfsAdHealth.compute_taiwan_ad_health(state.targets, state.scenario)

	var organic_budget: Variant = null
	if squadron_force != null:
		organic_budget = IjfsFiringCapacity.OrganicStrikeBudget.new(state.scenario, squadron_force, state.munitions, air_classes)

	var phase2 := IjfsDetection.aircraft_detect_target_ids(state.targets, state.scenario, squadron_force, air_classes_dict, 1.0, dice, int(ctx["isr_day"]))
	state.detection_log.append_array(phase2["log"])
	IjfsDetection.apply_detection_ids(state.targets, phase2["detected_ids"], ctx["current_day"])

	_run_strike_phase(state, ctx["current_day"], POST_AD_PHASE, attacked, skip_reasons, dice, capacity_budget, organic_budget, ctx["z_day"], release_rules, munition_filter)
	_append_final_skips(state, ctx["current_day"], attacked, skip_reasons, ctx["z_day"], release_rules)

	state.taiwan_ad_health_after = IjfsAdHealth.compute_taiwan_ad_health(state.targets, state.scenario)

	# MANPADS contest low-altitude squadrons (SEAD + strike) island-wide, same attrition gate as
	# the SAM layers. Draw order: after post-AD strikes, before the free shot.
	if ad_attrition_enabled:
		state.manpads_contest_log = IjfsManpads.contest_squadrons(state.targets, squadron_force, air_classes, dice)

	state.free_shot_log = IjfsEngagement.apply_post_phase_2_free_shot(
		squadron_force,
		air_classes,
		float(state.taiwan_ad_health_after.get("raw_sam_health", 0.0)),
		dice,
		ad_attrition_enabled,
	)

	var summary := summarize_run(state)
	if capacity_budget != null:
		summary["firing_capacity_utilization"] = capacity_budget.utilization()

	return _build_ledgers(state, current_day, summary)


# --- Strike phases (port of run_daily_ijfs._run_strike_phase / _append_final_skips / _skip_log) ---

static func _run_strike_phase(
	state: IjfsDailyState,
	current_day: int,
	phase: String,
	attacked: Dictionary,
	skip_reasons: Dictionary,
	dice: Dice,
	capacity_budget: Variant,
	organic_budget: Variant,
	z_day: Variant,
	release_rules: Variant,
	munition_filter: Variant,
) -> void:
	for target in IjfsTargeting.targets_to_attack(state.targets, z_day, release_rules):
		if attacked.has(target.target_id):
			continue
		var sel := IjfsTargeting.select_munition_with_doctrine(
			target, state.pairings, state.munitions, state.scenario, phase, munition_filter, capacity_budget, organic_budget)
		var pairing: Variant = sel["selected"]
		var doctrine_name: Variant = sel["doctrine_name"]
		var doctrine_selection: Variant = sel["selection"]
		if pairing == null:
			var reason: Variant = sel["reason"]
			skip_reasons[target.target_id] = [reason if reason != null else "no_compatible_pairing", doctrine_name, doctrine_selection]
			continue
		var mun: Variant = state.munitions.get(pairing.munition_id, null)
		var is_organic: bool = mun != null and mun.category == "Organic"
		var budget: Variant = organic_budget if is_organic else capacity_budget
		var reason_key: String = "organic_capacity_exhausted" if is_organic else "firing_capacity_exhausted"
		if budget != null and not budget.try_consume(pairing.munition_id):
			skip_reasons[target.target_id] = [reason_key, doctrine_name, doctrine_selection]
			continue
		# MANPADS interception (see IjfsManpads): rolled BEFORE the strike's own rolls, only for
		# rounds that will actually fly (mirrors resolve_strike's inventory sufficiency check).
		if mun != null:
			var rounds := int(pairing.rounds_expended_per_engagement)
			var will_fly: bool = is_organic or (mun as IjfsMunition).inventory_remaining >= rounds
			if will_fly:
				var intercept: Variant = IjfsManpads.roll_strike_interception(target, mun, state.targets, dice)
				if intercept != null:
					state.manpads_intercept_log.append(intercept)
					if intercept["intercepted"]:
						# Round spent, nothing delivered — mirror resolve_strike's inventory decrement.
						if not is_organic:
							(mun as IjfsMunition).inventory_remaining -= rounds
						state.strike_log.append(IjfsManpads.intercepted_strike_log(
							target, pairing, current_day, phase, doctrine_name, doctrine_selection))
						attacked[target.target_id] = true
						continue
		state.strike_log.append(IjfsStrike.resolve_strike(
			target, pairing, state.munitions, state.scenario, current_day, dice, phase, doctrine_name, doctrine_selection))
		attacked[target.target_id] = true


static func _append_final_skips(state: IjfsDailyState, current_day: int, attacked: Dictionary, skip_reasons: Dictionary, z_day: Variant, release_rules: Variant) -> void:
	for target in IjfsTargeting.targets_to_attack(state.targets, z_day, release_rules):
		if attacked.has(target.target_id):
			continue
		var entry: Array = skip_reasons.get(target.target_id, ["no_compatible_pairing", null, null])
		state.strike_log.append(_skip_log(target, current_day, entry[0], null, entry[1], entry[2]))


static func _skip_log(target: IjfsTarget, current_day: int, skip_reason: Variant, phase: Variant = null, doctrine_rule_name: Variant = null, doctrine_selection: Variant = null) -> Dictionary:
	var entry := target.to_dict()
	entry["current_day"] = current_day
	entry["phase"] = phase
	entry["doctrine_rule_name"] = doctrine_rule_name
	entry["doctrine_selection"] = doctrine_selection
	entry["attack_executed"] = false
	entry["skip_reason"] = skip_reason
	return entry


# --- Summary (port of logging_utils.summarize_run) ----------------------------------------------

static func summarize_run(state: IjfsDailyState) -> Dictionary:
	var target_counts: Dictionary = {}
	for target in state.targets:
		var counts: Dictionary = target_counts.get(target.category, {"total": 0, "destroyed": 0, "surviving": 0})
		counts["total"] += 1
		if target.destroyed:
			counts["destroyed"] += 1
		else:
			counts["surviving"] += 1
		target_counts[target.category] = counts

	var detections_by_mobility: Dictionary = {}
	var detections_by_category: Dictionary = {}
	for entry in state.detection_log:
		if entry.get("detected"):
			_inc(detections_by_mobility, entry["mobility"])
			_inc(detections_by_category, entry["category"])

	var destroyed_by_category: Dictionary = {}
	var suppressed_by_category: Dictionary = {}
	for entry in state.strike_log:
		if entry.get("destroyed"):
			_inc(destroyed_by_category, entry["category"])
		if entry.get("suppressed"):
			_inc(suppressed_by_category, entry["category"])
	for entry in state.engagement_log:
		if entry.get("destroyed") and entry.get("category") in IjfsEngagement.SAM_CATEGORIES:
			_inc(destroyed_by_category, entry["category"])
		if entry.get("suppressed") and entry.get("category") in IjfsEngagement.SAM_CATEGORIES:
			_inc(suppressed_by_category, entry["category"])

	var rounds_expended: Dictionary = {}
	var skipped: Dictionary = {}
	var executed := 0
	for entry in state.strike_log:
		if entry.get("attack_executed"):
			executed += 1
			var mid := String(entry.get("munition_id", ""))
			rounds_expended[mid] = int(rounds_expended.get(mid, 0)) + int(entry.get("rounds_expended", 0))
		else:
			_inc(skipped, String(entry.get("skip_reason", "unknown")))

	var skipped_total := 0
	for key in skipped:
		skipped_total += int(skipped[key])

	return {
		"target_counts_by_category_status": target_counts,
		"detections_by_mobility": detections_by_mobility,
		"detections_by_category": detections_by_category,
		"attacks": {
			"executed": executed,
			"skipped": skipped_total,
			"skipped_by_reason": skipped,
		},
		"destroyed_targets_by_category": destroyed_by_category,
		"suppressed_targets_by_category": suppressed_by_category,
		"rounds_expended_by_munition": rounds_expended,
		"red_air_losses": _sum_losses(state.contest_log) + _sum_losses(state.free_shot_log) + _sum_losses(state.manpads_contest_log),
		"manpads": {
			"ready_systems_by_to": IjfsManpads.ready_systems_by_to(state.targets),
			"interception_attempts": state.manpads_intercept_log.size(),
			"interceptions": _count_flag(state.manpads_intercept_log, "intercepted"),
			"squadron_losses": _sum_losses(state.manpads_contest_log),
		},
		"taiwan_ad_health_before": state.taiwan_ad_health_before,
		"taiwan_ad_health_after_missile_phase": state.taiwan_ad_health_after_missile_phase,
		"taiwan_ad_health_after_sead": state.taiwan_ad_health_after_sead,
		"taiwan_ad_health_after": state.taiwan_ad_health_after,
		"sead_pressure": {},
		"sead_engagements": state.engagement_log.size(),
		"sead_destroyed": _count_flag(state.engagement_log, "destroyed"),
		"sead_suppressed": _count_flag(state.engagement_log, "suppressed"),
		"contest_losses": _sum_losses(state.contest_log),
		"free_shot_losses": _sum_losses(state.free_shot_log),
		"exquisite_intel_overrides": state.exquisite_intel_overrides.duplicate(),
		"warnings": state.warnings.duplicate(),
	}


# --- Ledgers (in-memory replacement for write_outputs) ------------------------------------------

static func _build_ledgers(state: IjfsDailyState, current_day: int, summary: Dictionary) -> Dictionary:
	var sorted_targets: Array[IjfsTarget] = state.targets.duplicate()
	sorted_targets.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
	var target_status: Array = []
	for target in sorted_targets:
		target_status.append(target.to_dict())

	var inventory: Dictionary = {}
	var sorted_mids: Array = state.munitions.keys()
	sorted_mids.sort()
	for mid in sorted_mids:
		var mun: IjfsMunition = state.munitions[mid]
		inventory[mid] = {
			"munition_id": mun.munition_id,
			"name": mun.name,
			"category": mun.category,
			"inventory_remaining": mun.inventory_remaining,
			"rounds_per_engagement_default": mun.rounds_per_engagement_default,
			"display_label": mun.display_label if mun.display_label != "" else null,
		}

	var air_oob_after: Variant = null
	if state.squadron_force != null:
		var squadrons: Array = []
		for sq: IjfsSquadron in (state.squadron_force as Array):
			squadrons.append({
				"squadron_id": sq.squadron_id,
				"class": sq.aircraft_class,
				"role": sq.role,
				"initial": sq.initial,
				"alive": sq.alive,
				"rtb_today": sq.rtb_today,
				"losses_today": sq.losses_today,
			})
		air_oob_after = {"model_version": 3, "squadrons": squadrons, "provenance": {}}

	return {
		"metadata": {
			"current_day": current_day,
			"seed": state.seed,
			"source_files": state.source_files.duplicate(),
			"created_by": "ijfs_standalone",
		},
		"detection_log": state.detection_log,
		"strike_log": state.strike_log,
		"target_status_after": target_status,
		"munition_inventory_after": inventory,
		"engagement_log": state.engagement_log,
		"contest_log": state.contest_log,
		"free_shot_log": state.free_shot_log,
		"manpads_intercept_log": state.manpads_intercept_log,
		"manpads_contest_log": state.manpads_contest_log,
		"air_oob_after": air_oob_after,
		"summary": summary,
	}


# --- Continuity (in-memory equivalent of the loader reload reset) -------------------------------

static func carry_to_next_day(state: IjfsDailyState) -> void:
	# Mirrors loaders.load_targets's runtime-reload branch: suppression + sead_result clear each
	# day; destroyed / known_to_red / last_detected_day / detected_this_turn persist. Munitions and
	# squadron_force carry forward unchanged (their attrition is already applied in-place).
	for target in state.targets:
		target.suppressed = false
		target.suppressed_this_turn = false
		target.sead_result = ""


# --- helpers ------------------------------------------------------------------------------------

static func _inc(counter: Dictionary, key: Variant) -> void:
	counter[key] = int(counter.get(key, 0)) + 1


static func _sum_losses(log: Array) -> int:
	var total := 0
	for entry in log:
		total += int(entry.get("losses", 0))
	return total


static func _count_flag(log: Array, flag: String) -> int:
	var count := 0
	for entry in log:
		if entry.get(flag):
			count += 1
	return count
