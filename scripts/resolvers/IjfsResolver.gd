class_name IjfsResolver
extends RefCounted

## Pure resolver for the D4 IJFS (Red joint/air-missile fires) phase (refactor_audit item 10,
## Phase C): syncs maneuver targets to the live OOB, applies the activity-posture detectability
## bias, runs the multi-day prelanding warmup (first IJFS) or one plain daily cycle, and computes
## the writeback D3 + the ground-casualty linkage consume. Derives its per-day "ijfs:<turn>:<i>"
## substreams from the passed base dice (SeededDice.derive is a pure hash — the base combat
## stream is never consumed). Mutates the passed IjfsDailyState/Brigade Resources — the
## sanctioned pattern; no autoload/engine access. GameState's wrapper owns the lazy ijfs_state
## build, the _ijfs_day/last_* field writes, and the EventBus.ijfs_resolved emit.

## Number of IJFS daily cycles run on the FIRST IJFS of the game when the scenario config
## carries no prelanding.days (the pre-invasion air campaign). Fallback only.
const PRE_INVASION_DAYS_FALLBACK := 4


## Returns {"ledgers": Dictionary (IjfsEngine.run_daily output), "writeback": IjfsWriteback}.
## ijfs_day: GameState._ijfs_day going in (0 = the warmup has not run yet).
static func resolve(ijfs_state: IjfsDailyState, brigades: Dictionary, turn_number: int, ijfs_day: int, dice: Dice) -> Dictionary:
	# D4-H (2d follow-up): retire maneuver targets whose battalions died (IJFS or ground combat).
	sync_maneuver_targets_to_oob(ijfs_state, brigades)
	# MANPADS ride with the infantry: ground losses in a TO shrink its MANPADS pools (after the
	# maneuver sync so this turn's ground casualties are already reflected). Zero dice.
	sync_manpads_to_oob(ijfs_state)
	# D4-H (2c-ii): recently-active maneuver units present an "active" posture (more detectable).
	update_maneuver_posture(ijfs_state, brigades)
	# On the FIRST IJFS of the game, run the multi-day prelanding warmup campaign so exquisite
	# intel, posture override, SEAD/AD rules, and munition filter are applied (port of TIV's
	# ijfs_prewarmup._run_warmup_locked). Later turns run one plain cycle.
	var ledgers: Dictionary = {}
	if ijfs_day == 0:
		var scenario_data: Dictionary = ijfs_state.scenario
		var prelanding: Dictionary = scenario_data.get("prelanding", {})
		var warmup_days := int(prelanding.get("days", PRE_INVASION_DAYS_FALLBACK))
		var rules: Dictionary = prelanding.get("rules", {})
		var exquisite_intel: Dictionary = prelanding.get("intel", {}).get("exquisite_intel", {})
		var attrition_profile: String = prelanding.get("attrition_profile", "even")
		var firing_capacity_config: Dictionary = scenario_data.get("red_firing_capacity", {})
		var release_rules: Array = scenario_data.get("target_release", [])
		for i in range(warmup_days):
			# carry_to_next_day persists destroyed/known/inventory and clears per-day suppression
			# flags (so only the final pre-invasion day's suppression survives; destruction
			# accumulates).
			if i > 0:
				IjfsEngine.carry_to_next_day(ijfs_state)
			var ijfs_dice := _derive_day_dice(dice, turn_number, i)
			var x_day := i + 1
			var z_day := x_day - warmup_days - 1
			var warmup := build_warmup_context(x_day, z_day, warmup_days, rules, exquisite_intel, attrition_profile, firing_capacity_config, release_rules)
			ledgers = IjfsEngine.run_daily(ijfs_state, ijfs_dice, z_day, warmup)
	else:
		# Subsequent turns: single plain day (no warmup context).
		IjfsEngine.carry_to_next_day(ijfs_state)
		ledgers = IjfsEngine.run_daily(ijfs_state, _derive_day_dice(dice, turn_number, 0), turn_number)
	return {"ledgers": ledgers, "writeback": compute_writeback(ijfs_state, ledgers)}


## Independent IJFS substream per day — NEVER consumes the combat dice.
static func _derive_day_dice(dice: Dice, turn_number: int, day_index: int) -> Dice:
	if dice is SeededDice:
		return dice.derive("ijfs:%d:%d" % [turn_number, day_index])
	return SeededDice.new(hash("ijfs:%d:%d" % [turn_number, day_index]))


## Build the warmup_context dict for one prelanding day (port of TIV
## ijfs_prewarmup._run_warmup_locked's per-day context construction). ZERO dice consumed.
static func build_warmup_context(
	x_day: int, z_day: int, total_days: int,
	rules: Dictionary, exquisite_intel: Dictionary,
	attrition_profile: String,
	firing_capacity_config: Dictionary,
	release_rules: Array,
) -> Dictionary:
	var mult := IjfsWarmup.profile_multiplier(attrition_profile, x_day, total_days)
	var day_firing := IjfsWarmup.scale_firing_capacity(firing_capacity_config, mult)
	return {
		"x_day": x_day,
		"z_day": z_day,
		"sead_enabled": rules.get("sead_enabled", false),
		"ad_attrition_enabled": rules.get("ad_attrition_enabled", false),
		"munition_filter": rules.get("munition_filter", {}),
		"posture_default_override": rules.get("posture_default_override"),
		"release_rules": release_rules,
		"firing_capacity_config": day_firing,
		"exquisite_intel": exquisite_intel,
	}


## D4-H (2c-ii): bias IJFS detectability toward recently-active Green maneuver units. A brigade
## that moved or fought last turn presents an "active" posture, so its maneuver-unit IJFS targets
## use the higher detectability_active label (and active posture/satellite multipliers) in
## IjfsDetection; otherwise they stay "hiding". Pure data nudge — no detection-math change.
## Golden-safe: on turn 1 all activity flags are false, so every maneuver target stays "hiding".
static func update_maneuver_posture(ijfs_state: IjfsDailyState, brigades: Dictionary) -> void:
	for target_value in ijfs_state.targets:
		var target: IjfsTarget = target_value
		if target.category != "Maneuver Units":
			continue
		var brigade_id := String(target.metadata.get("brigade_id", ""))
		if brigade_id == "":
			continue
		var brigade: Brigade = brigades.get(brigade_id)
		if brigade == null:
			continue
		target.posture = "active" if (brigade.moved_last_turn or brigade.fought_last_turn) else "hiding"


## MANPADS layer (2026-07-10): Stingers are distributed across TO ground forces, so a TO's pool
## cannot outlive its infantry. Per TO, survival fraction = alive / total "Maneuver Units" IJFS
## targets (the engine's own ledger of ground battalions — no new state); each MANPADS bin's
## systems_remaining is capped at round(systems_represented × fraction). Monotonic (cap only
## shrinks, usage/bombardment may already hold stock lower — min keeps), idempotent, zero dice.
static func sync_manpads_to_oob(ijfs_state: IjfsDailyState) -> void:
	var total_by_to: Dictionary = {}
	var alive_by_to: Dictionary = {}
	for target_value in ijfs_state.targets:
		var target: IjfsTarget = target_value
		if target.category != "Maneuver Units":
			continue
		var to_key := int(target.metadata.get("to_number", 0))
		total_by_to[to_key] = int(total_by_to.get(to_key, 0)) + 1
		if not target.destroyed:
			alive_by_to[to_key] = int(alive_by_to.get(to_key, 0)) + 1
	for target_value in ijfs_state.targets:
		var target: IjfsTarget = target_value
		if target.category != IjfsManpads.CATEGORY or target.destroyed:
			continue
		var to_key := int(target.metadata.get("to_number", 0))
		var total := int(total_by_to.get(to_key, 0))
		if total == 0:
			continue
		var fraction := float(int(alive_by_to.get(to_key, 0))) / float(total)
		var cap := int(roundf(float(int(target.metadata.get("systems_represented", 0))) * fraction))
		target.metadata["systems_remaining"] = mini(IjfsManpads.systems_remaining(target), cap)


## D4-H (2d follow-up): keep the live "Maneuver Units" IJFS target count in sync with the OOB
## each turn. For each (brigade_id, unit_type) group, if more targets are still alive than the
## brigade has battalions of that type, mark the excess `destroyed` (highest target_id first,
## deterministic). Only ever sets destroyed — never resurrects — so detection continuity
## (known_to_red/last_detected_day) for survivors is preserved, and carry_to_next_day keeps the
## flag. Golden-safe: when IJFS runs on turn 1 the OOB is still full → no target is touched.
static func sync_maneuver_targets_to_oob(ijfs_state: IjfsDailyState, brigades: Dictionary) -> void:
	var live_by_key: Dictionary = {}
	for target_value in ijfs_state.targets:
		var target: IjfsTarget = target_value
		if target.category != "Maneuver Units" or target.destroyed:
			continue
		var key := "%s|%s" % [String(target.metadata.get("brigade_id", "")), String(target.metadata.get("unit_type", ""))]
		if not live_by_key.has(key):
			live_by_key[key] = []
		(live_by_key[key] as Array).append(target)
	for key in live_by_key:
		var parts := String(key).split("|", true, 1)
		var brigade_id := parts[0]
		var unit_type := parts[1] if parts.size() > 1 else ""
		var current_qty := 0
		var brigade: Brigade = brigades.get(brigade_id)
		if brigade != null and not brigade.destroyed:
			for battalion in brigade.composition:
				if battalion.type == unit_type:
					current_qty += battalion.qty
		var live_targets: Array = live_by_key[key]
		var excess := live_targets.size() - current_qty
		if excess > 0:
			live_targets.sort_custom(func(a: IjfsTarget, b: IjfsTarget) -> bool: return a.target_id > b.target_id)
			for i in range(excess):
				(live_targets[i] as IjfsTarget).destroyed = true


## Consume IJFS maneuver casualties: remove each struck Green/ROC battalion from the OOB before
## ground combat. Each casualty (battalion_id/brigade_id/unit_type) decrements one qty of the
## matching battalion type in that brigade's composition (capped at 0). A brigade whose
## composition is fully depleted is marked destroyed so it no longer fights or holds a hex.
## NOTE: ijfs_state (and its maneuver targets) is built once per scenario, so across many turns a
## removed battalion can still appear as a target; the qty cap keeps this safe (never negative).
static func apply_maneuver_casualties(casualties: Array, brigades: Dictionary) -> void:
	for casualty_value in casualties:
		var casualty: Dictionary = casualty_value
		var brigade_id := String(casualty.get("brigade_id", ""))
		var unit_type := String(casualty.get("unit_type", ""))
		if brigade_id == "" or unit_type == "":
			continue
		var brigade: Brigade = brigades.get(brigade_id)
		if brigade == null:
			continue
		for battalion in brigade.composition:
			if battalion.type == unit_type and battalion.qty > 0:
				battalion.qty -= 1
				break
		var any_left := false
		for battalion in brigade.composition:
			if battalion.qty > 0:
				any_left = true
				break
		if not any_left:
			brigade.destroyed = true


## Aggregates the IJFS ledgers into the writeback seam D3 (anti-ship) and the ground-casualty
## linkage consume. Anti-ship attrition is read from the CUMULATIVE target state
## (target.destroyed persists across days; target.suppressed reflects the latest day) so the
## multi-day pre-invasion campaign feeds the firing plan. Keyed by encode_key("<to>:<type>").
## INVARIANT: antiship_destroyed_by_type is a running TOTAL (all days so far), NOT a per-turn
## delta — AntishipResolver relies on this to decrement from original_quantity idempotently.
## (Reads ijfs_state directly, not `ledgers`, because cumulative state spans run_daily days.)
static func compute_writeback(ijfs_state: IjfsDailyState, ledgers: Dictionary) -> IjfsWriteback:
	var strike_log: Array = ledgers["strike_log"]
	var engagement_log: Array = ledgers["engagement_log"]

	var antiship_destroyed_by_type: Dictionary = {}
	var antiship_suppressed_by_type: Dictionary = {}
	var maneuver_casualties: Array = []

	for target_value in ijfs_state.targets:
		var target: IjfsTarget = target_value
		if String(target.category) != "Anti-Ship Systems":
			continue
		var asm: Dictionary = target.metadata
		if not (asm.has("to_number") and asm.has("type_id")):
			continue
		var rep := int(asm.get("systems_represented", 1))
		var ask := AntishipCalculator.encode_key(int(asm["to_number"]), int(asm["type_id"]))
		if target.destroyed:
			antiship_destroyed_by_type[ask] = int(antiship_destroyed_by_type.get(ask, 0)) + rep
		elif target.suppressed:
			antiship_suppressed_by_type[ask] = int(antiship_suppressed_by_type.get(ask, 0)) + rep

	for entry in strike_log:
		if not entry.get("attack_executed"):
			continue
		var category := String(entry.get("category", ""))
		if category == "Maneuver Units" and entry.get("destroyed"):
			# Faithful port of ijfs_maneuver_writeback_service.compute_maneuver_writeback.
			var metadata: Dictionary = entry.get("metadata", {})
			var unit_id: Variant = metadata.get("battalion_id", metadata.get("unit_id", null))
			if unit_id == null or String(unit_id) == "":
				continue
			maneuver_casualties.append({
				"battalion_id": unit_id,
				"brigade_id": metadata.get("brigade_id", null),
				"to": metadata.get("to_number", null),
				"unit_type": metadata.get("unit_type", null),
				"subcategory": entry.get("subcategory", null),
			})

	var sam_destroyed := 0
	var sam_suppressed := 0
	for entry in engagement_log:
		if entry.get("destroyed"):
			sam_destroyed += 1
		if entry.get("suppressed"):
			sam_suppressed += 1

	var writeback := IjfsWriteback.new()
	writeback.antiship_destroyed_by_type = antiship_destroyed_by_type
	writeback.antiship_suppressed_by_type = antiship_suppressed_by_type
	writeback.maneuver_casualties = maneuver_casualties
	writeback.sam_destroyed = sam_destroyed
	writeback.sam_suppressed = sam_suppressed
	return writeback
