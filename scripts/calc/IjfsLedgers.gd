class_name IjfsLedgers
extends RefCounted

## The IJFS day's REPORTING half: the run summary (port of ijfs_standalone
## logging_utils.summarize_run) and the in-memory ledger bundle that replaces the oracle's
## write_outputs file IO. Pure — it reads the finished IjfsDailyState and mutates nothing.
##
## Extracted from IjfsEngine 2026-08-01 (plan 0060). The engine was at its dependency ceiling of 14
## and plan 0060 adds three collaborators to it, so the ceiling had to be PAID rather than raised.
## Reporting was the right thing to move: it is the only part of the engine that names IjfsSquadron
## and IjfsMunition purely to serialize them, and a day's orchestration should not also own the
## shape of the record it leaves behind.


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

	var attacks := _attack_totals(state.strike_log)

	return {
		"target_counts_by_category_status": target_counts,
		"detections_by_mobility": detections_by_mobility,
		"detections_by_category": detections_by_category,
		"attacks": attacks["attacks"],
		"destroyed_targets_by_category": destroyed_by_category,
		"suppressed_targets_by_category": suppressed_by_category,
		"rounds_expended_by_munition": attacks["rounds_expended"],
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


## Executed/skipped counts and per-munition rounds, in one pass over the strike log.
static func _attack_totals(strike_log: Array) -> Dictionary:
	var rounds_expended: Dictionary = {}
	var skipped: Dictionary = {}
	var executed := 0
	for entry in strike_log:
		if entry.get("attack_executed"):
			executed += 1
			var munition_id := String(entry.get("munition_id", ""))
			rounds_expended[munition_id] = int(rounds_expended.get(munition_id, 0)) + int(entry.get("rounds_expended", 0))
		else:
			_inc(skipped, String(entry.get("skip_reason", "unknown")))

	var skipped_total := 0
	for key in skipped:
		skipped_total += int(skipped[key])

	return {
		"attacks": {"executed": executed, "skipped": skipped_total, "skipped_by_reason": skipped},
		"rounds_expended": rounds_expended,
	}


# --- Ledgers (in-memory replacement for write_outputs) ------------------------------------------

static func build_ledgers(state: IjfsDailyState, current_day: int, summary: Dictionary) -> Dictionary:
	var sorted_targets: Array[IjfsTarget] = state.targets.duplicate()
	sorted_targets.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id < b.target_id)
	var target_status: Array = []
	for target in sorted_targets:
		target_status.append(target.to_dict())

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
		"munition_inventory_after": _munition_inventory(state.munitions),
		"engagement_log": state.engagement_log,
		"contest_log": state.contest_log,
		"free_shot_log": state.free_shot_log,
		"manpads_intercept_log": state.manpads_intercept_log,
		"manpads_contest_log": state.manpads_contest_log,
		"air_oob_after": build_air_oob(state),
		"summary": summary,
	}


static func _munition_inventory(munitions: Dictionary) -> Dictionary:
	var inventory: Dictionary = {}
	var sorted_ids: Array = munitions.keys()
	sorted_ids.sort()
	for munition_id in sorted_ids:
		var munition: IjfsMunition = munitions[munition_id]
		inventory[munition_id] = {
			"munition_id": munition.munition_id,
			"name": munition.munition_name,
			"category": munition.category,
			"inventory_remaining": munition.inventory_remaining,
			"rounds_per_engagement_default": munition.rounds_per_engagement_default,
			"display_label": munition.display_label if munition.display_label != "" else null,
		}
	return inventory


## Red's per-squadron air order of battle at the end of the day, or null when the run carries no
## force at all.
##
## `kind` (manned/unmanned) is stamped here rather than left for the consumer to re-derive by joining
## air_classes.json on the class name — the record is read by research tooling that has no access to
## the data files.
##
## Both lookups below are HARD INDEXES, deliberately. An earlier draft used `classes.get(cls_name,
## {})` and emitted `kind: ""` when it missed, which is the get-with-default-across-a-boundary this
## project forbids (non-negotiable #2, the exquisite-intel incident) wearing a push_error as a
## disguise: it logged and then published a row whose airframes were neither manned nor unmanned. The
## OOB<->air-classes join is only checked by tools/validate_ijfs_data.gd, i.e. at gate time and not at
## load, so a missing class has to fail HERE rather than be papered over.
##
## model_version 4 (2026-08-01): losses_campaign added, and losses_today changed MEANING from
## campaign-cumulative to per-day. A consumer reading v3 semantics off a v4 payload would silently
## under-report, which is exactly what the version is for.
##
## `kind` was added later the same day (plan 0059) and deliberately did NOT bump the version: it is
## purely additive, and no v4 payload had ever been persisted anywhere — this ledger reached no
## fixture, record or API until 0059 surfaced it — so no consumer can be misled by a widened row. Bump
## only when a field's MEANING moves, as losses_today's did.
static func build_air_oob(state: IjfsDailyState) -> Variant:
	if state.squadron_force == null:
		return null
	var classes: Dictionary = {}
	if state.air_classes != null:
		classes = (state.air_classes as Dictionary)["classes"]
	var squadrons: Array = []
	for squadron: IjfsSquadron in (state.squadron_force as Array):
		if not classes.has(squadron.aircraft_class):
			push_error("IjfsLedgers: squadron %s has class '%s' with no air_classes entry" % [
				squadron.squadron_id, squadron.aircraft_class])
			assert(false, "air OOB references a class absent from air_classes")
		var cls: Dictionary = classes[squadron.aircraft_class]
		squadrons.append({
			"squadron_id": squadron.squadron_id,
			"class": squadron.aircraft_class,
			"kind": cls["kind"],
			"role": squadron.role,
			"initial": squadron.initial,
			"alive": squadron.alive,
			"rtb_today": squadron.rtb_today,
			"losses_today": squadron.losses_today,
			"losses_campaign": squadron.losses_campaign,
		})
	return {"model_version": 4, "squadrons": squadrons, "provenance": {}}


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
