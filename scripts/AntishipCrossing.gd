class_name AntishipCrossing
extends RefCounted

## D3-B3 — anti-ship crossing-damage model. Faithful port of the COUNT-BASED pipeline in TIV
## services/antiship_crossing.py: resolve what ships are hit / damaged / sunk when anti-ship missiles
## are fired at the amphibious fleet during the crossing.
##
## Seven stages, each consuming the injected Dice in source order (every RNG-consuming stage sorts
## its inputs first so the result is independent of caller iteration order):
##   1. launches      — systems firing -> missiles launched per munition, drawing the global munition
##                      pools (per-munition or shared store group); range tier gates participation;
##                      half of any unfillable shortfall still launches (partial fire).
##   2. in-flight      — per-munition failure draw against in_flight_failure_rate.
##   3. interception   — escort ships (CG/DDG/FFG/FFL) intercept missiles in groups of `group_size`.
##   4. homing         — surviving missiles home on the sent fleet weighted by target_value, with
##                      per-munition decoy discrimination.
##   5. terminal def.  — per-(ship_type, munition) terminal-defense roll; survivors become hits.
##   6. damage         — hits resolve into sunk/damaged hulls (fresh -> damaged -> sunk; re-hit
##                      fragility via damaged_hull_neut_multiplier; overkill -> wasted_hits).
##
## SCOPE (documented divergence — see PLAN.md Decisions 2026-06-27 D3-B3): TIV's live
## `resolve_crossing_damage` dispatches stages 3 and 5/6 to PER-HULL variants
## (`_apply_interception_per_hull`, `_apply_terminal_defense_and_resolve_damage_per_hull`) that track
## individual escort magazines (hq10/hhq9 via `ship_ammo`) and damage-status combat multipliers
## (`ship_readiness_policy`) — subsystems HexCombat does not model. This port uses the equivalent
## COUNT-BASED stages (also present in the TIV source); every `test_antiship_crossing.py` assertion
## holds under them (escort attempts/success are set so per-hull ammo never binds, and the damage
## math is identical). Per-hull escort-magazine depletion is deferred (Open Question — when ship
## magazines are modeled). The RNG mirrors source formulas + draw order via the injected Dice, not
## Python's PRNG bitstream (per AGENTS.md).
##
## Result is a Dictionary of per-stage ledgers plus computed `missile_stage_totals` (missile-event
## counts) and `casualty_totals` (hull counts) — deliberately separate units, never summed.

const ESCORT_SHIP_TYPES := ["CG", "DDG", "FFG", "FFL"]
const VALID_RANGE_TIERS := ["own_to", "neighboring", "whole_island"]


## ship_snapshots: Array of ShipState OR Dictionary{ship_type, surviving_sent}.
## systems_fired: Array of Dictionary rows {location|to, type, systems_fired}.
## active_tos / to_adjacency: theater data for range-tier gating (only needed beyond own_to).
static func resolve_crossing_damage(
		systems_fired: Array,
		ship_snapshots: Array,
		combat_catalog: Dictionary,
		crossing_config: Dictionary,
		target_tos: Array,
		dice: Dice,
		active_tos: Array = [],
		to_adjacency: Dictionary = {}) -> Dictionary:
	# Fail loudly on broken config rather than silently producing zero damage.
	validate_combat_catalog(combat_catalog)
	validate_crossing_config(crossing_config)

	var result := _new_result()
	if systems_fired.is_empty():
		return _finalize(result)

	var snaps := _normalize_snapshots(ship_snapshots)

	var munitions: Dictionary = combat_catalog.get("munitions", {})
	var launcher_catalog: Dictionary = combat_catalog.get("launchers", {})
	var store_groups: Dictionary = combat_catalog.get("store_groups", {})

	# Each grouped munition draws from its shared store budget (individual quantity ignored).
	var munition_to_group: Dictionary = {}
	for name in munitions.keys():
		var grp: Variant = munitions[name].get("store_group")
		if grp != null:
			munition_to_group[name] = grp
	var munition_pool: Dictionary = {}
	for name in munitions.keys():
		if not munition_to_group.has(name):
			munition_pool[name] = int(munitions[name].get("quantity", 0))
	var group_pool: Dictionary = {}
	for grp in store_groups.keys():
		group_pool[grp] = int(store_groups[grp].get("quantity", 0))

	var launched := _resolve_launches(
		systems_fired, launcher_catalog, munition_pool, group_pool,
		munition_to_group, target_tos, active_tos, to_adjacency, result)
	var surviving := _apply_in_flight_failures(launched, munitions, dice, result)
	var leakers := _apply_interception(surviving, snaps, crossing_config, dice, result)
	var homings := _apply_homing(leakers, snaps, crossing_config, munitions, dice, result)
	var hits := _apply_terminal_defense(homings, crossing_config, munitions, dice, result)
	_resolve_damage(hits, snaps, crossing_config, munitions, dice, result)

	return _finalize(result)


# --- stage 1: launches ---------------------------------------------------------------------------

static func _resolve_launches(
		systems_fired: Array, launcher_catalog: Dictionary, munition_pool: Dictionary,
		group_pool: Dictionary, munition_to_group: Dictionary, target_tos: Array,
		active_tos: Array, to_adjacency: Dictionary, result: Dictionary) -> Dictionary:
	var target_set: Dictionary = {}
	for t in target_tos:
		if str(t).strip_edges() != "":
			target_set[int(t)] = true

	var launched: Dictionary = {}

	# Sort rows so the global-pool drawdown order is independent of input order.
	var rows := systems_fired.duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la := str(a.get("location", a.get("to", "")))
		var lb := str(b.get("location", b.get("to", "")))
		if la != lb:
			return la < lb
		return str(a.get("type", "")) < str(b.get("type", "")))

	for row in rows:
		var systems := int(row.get("systems_fired", 0))
		if systems <= 0:
			continue
		var type_id := str(row.get("type", "")).replace("Type_", "").strip_edges()
		if not launcher_catalog.has(type_id):
			result["warnings"].append("No combat catalog entry for launcher type %s" % type_id)
			continue
		var spec: Dictionary = launcher_catalog[type_id]

		var source_to: Variant = _parse_source_to(row.get("location", row.get("to")))
		if source_to != null and not target_set.is_empty():
			var reachable := _reachable_tos(
				int(source_to), str(spec.get("range_tier", "own_to")), active_tos, to_adjacency)
			var in_range := false
			for t in target_set.keys():
				if reachable.has(t):
					in_range = true
					break
			if not in_range:
				continue  # out of range of every targeted TO

		var need := systems * int(spec.get("missiles_per_launcher", 0))
		var loadout: Array = spec.get("missiles", [])
		if need <= 0 or loadout.is_empty():
			continue

		var remaining := need
		for munition in loadout:
			if remaining <= 0:
				break
			var take := _draw_from_pool(munition, remaining, munition_pool, group_pool, munition_to_group)
			if take > 0:
				_add(launched, munition, take)
				remaining -= take

		# Half of the unfillable shortfall still launches (destroyed-missile partial fire),
		# attributed to the primary munition; it does not draw the pool.
		if remaining > 0:
			var partial := int(remaining * 0.5)
			if partial > 0:
				_add(launched, loadout[0], partial)

	result["launched_by_munition"] = launched
	return launched


static func _draw_from_pool(
		munition: Variant, want: int, munition_pool: Dictionary,
		group_pool: Dictionary, munition_to_group: Dictionary) -> int:
	if munition_to_group.has(munition):
		var group: Variant = munition_to_group[munition]
		var available := int(group_pool.get(group, 0))
		var take := mini(want, available)
		if take > 0:
			group_pool[group] = available - take
		return take
	var avail := int(munition_pool.get(munition, 0))
	var taken := mini(want, avail)
	if taken > 0:
		munition_pool[munition] = avail - taken
	return taken


# --- stage 2: in-flight failures -----------------------------------------------------------------

static func _apply_in_flight_failures(
		launched: Dictionary, munitions: Dictionary, dice: Dice, result: Dictionary) -> Dictionary:
	var surviving: Dictionary = {}
	var keys := launched.keys()
	keys.sort()
	for munition in keys:
		var count := int(launched[munition])
		var rate := _cfg_num(munitions.get(munition, {}), "in_flight_failure_rate", 0.0)
		var failed := 0
		for _i in range(count):
			if dice.randf() < rate:
				failed += 1
		_add(result["failed_in_flight_by_munition"], munition, failed)
		surviving[munition] = count - failed
	return surviving


# --- stage 3: escort interception (count-based) --------------------------------------------------

static func _build_escort_defenders(snaps: Array, escort_config: Dictionary) -> Array:
	var defenders: Array = []
	for snap in snaps:
		var ship_type: String = snap["ship_type"]
		if not escort_config.has(ship_type):
			continue
		var cfg: Dictionary = escort_config[ship_type]
		for _i in range(int(snap["surviving_sent"])):
			defenders.append({
				"attempts": int(_cfg_num(cfg, "attempts", 0)),
				"success_prob": _cfg_num(cfg, "success_prob", 0.0),
			})
	return defenders


static func _apply_interception(
		surviving: Dictionary, snaps: Array, crossing_config: Dictionary,
		dice: Dice, result: Dictionary) -> Dictionary:
	var defenders := _build_escort_defenders(snaps, crossing_config.get("escort_interception", {}))
	var group_size := int(crossing_config.get("missile_group_size", 4))
	if group_size <= 0:
		group_size = 4

	# Flatten surviving missiles (sorted munition expand) then shuffle so groups mix munition types.
	var flat: Array = []
	var keys := surviving.keys()
	keys.sort()
	for munition in keys:
		for _i in range(int(surviving[munition])):
			flat.append(munition)
	flat = _shuffled(flat, dice)

	var leakers: Dictionary = {}
	if defenders.is_empty():
		for munition in surviving.keys():
			leakers[munition] = int(surviving[munition])
		result["leakers_by_munition"] = leakers
		return leakers

	var start := 0
	while start < flat.size():
		var group: Array = flat.slice(start, start + group_size)
		start += group_size
		var available: Array = []
		for d in defenders:
			if int(d["attempts"]) > 0:
				available.append(d)
		if available.is_empty():
			for munition in group:
				_add(leakers, munition, 1)
			continue
		var defender: Dictionary = _choice(available, dice)
		defender["attempts"] = int(defender["attempts"]) - 1
		var success_prob: float = defender["success_prob"]
		for munition in group:
			if dice.randf() < success_prob:
				_add(result["intercepted_by_munition"], munition, 1)
			else:
				_add(leakers, munition, 1)

	result["leakers_by_munition"] = leakers
	return leakers


# --- stage 4: homing -----------------------------------------------------------------------------

static func _weighted_pool(snaps: Array, ship_profiles: Dictionary, include_decoys: bool) -> Array:
	var types: Array = []
	var weights: Array = []
	for snap in snaps:
		if int(snap["surviving_sent"]) <= 0:
			continue
		var ship_type: String = snap["ship_type"]
		if not ship_profiles.has(ship_type):
			continue
		var profile: Dictionary = ship_profiles[ship_type]
		if bool(profile.get("is_decoy", false)) and not include_decoys:
			continue
		var weight := _cfg_num(profile, "target_value", 1.0) * float(int(snap["surviving_sent"]))
		if weight <= 0.0:
			continue
		types.append(ship_type)
		weights.append(weight)
	return [types, weights]


static func _apply_homing(
		leakers: Dictionary, snaps: Array, crossing_config: Dictionary,
		munitions: Dictionary, dice: Dice, result: Dictionary) -> Dictionary:
	var ship_profiles: Dictionary = crossing_config.get("ship_profiles", {})
	var discrimination: Dictionary = crossing_config.get("discrimination_probabilities", {})

	for snap in snaps:
		if int(snap["surviving_sent"]) > 0 and not ship_profiles.has(snap["ship_type"]):
			result["warnings"].append(
				"Ship type '%s' has no crossing-config profile; it cannot be targeted by antiship missiles" % snap["ship_type"])

	var real_pool := _weighted_pool(snaps, ship_profiles, false)
	var all_pool := _weighted_pool(snaps, ship_profiles, true)
	var real_types: Array = real_pool[0]
	var real_weights: Array = real_pool[1]
	var all_types: Array = all_pool[0]
	var all_weights: Array = all_pool[1]

	var homings: Dictionary = {}
	if all_types.is_empty():
		result["warnings"].append("No ships in the sent pool to target")
		return homings

	var decoy_types: Dictionary = {}
	for snap in snaps:
		if bool(ship_profiles.get(snap["ship_type"], {}).get("is_decoy", false)):
			decoy_types[snap["ship_type"]] = true

	var keys := leakers.keys()
	keys.sort()
	for munition in keys:
		var count := int(leakers[munition])
		if count <= 0:
			continue
		var ability := str(munitions.get(munition, {}).get("discrimination_ability", "Low"))
		var discr_prob := _cfg_num(discrimination, ability, 0.0)

		var n_discriminating := 0
		for _i in range(count):
			if dice.randf() < discr_prob:
				n_discriminating += 1

		var targets: Array = []
		if not real_types.is_empty() and n_discriminating > 0:
			for idx in dice.weighted_choices(real_weights, n_discriminating):
				targets.append(real_types[idx])
		else:
			n_discriminating = 0
		var n_remaining := count - n_discriminating
		if n_remaining > 0:
			for idx in dice.weighted_choices(all_weights, n_remaining):
				targets.append(all_types[idx])

		for target in targets:
			if decoy_types.has(target):
				_add(result["decoy_hits_by_munition"], munition, 1)
			else:
				if not homings.has(target):
					homings[target] = {}
				homings[target][munition] = int(homings[target].get(munition, 0)) + 1
	return homings


# --- stage 5: terminal defense -------------------------------------------------------------------

static func _terminal_defense_prob(
		missile_susceptibility: String, ship_capability: String, td_config: Dictionary) -> float:
	var base := _cfg_num(td_config, "base_probability", 0.0)
	base += _cfg_num(td_config.get("susceptibility_adjustment", {}), missile_susceptibility, 0.0)
	base += _cfg_num(td_config.get("capability_adjustment", {}), ship_capability, 0.0)
	return clampf(base, 0.0, 1.0)


static func _apply_terminal_defense(
		homings: Dictionary, crossing_config: Dictionary, munitions: Dictionary,
		dice: Dice, result: Dictionary) -> Dictionary:
	var ship_profiles: Dictionary = crossing_config.get("ship_profiles", {})
	var td_config: Dictionary = crossing_config.get("terminal_defense", {})

	var hits: Dictionary = {}
	var ship_keys := homings.keys()
	ship_keys.sort()
	for ship_type in ship_keys:
		var by_munition: Dictionary = homings[ship_type]
		var capability := str(ship_profiles.get(ship_type, {}).get("terminal_defense_capability", "None"))
		var mun_keys := by_munition.keys()
		mun_keys.sort()
		for munition in mun_keys:
			var count := int(by_munition[munition])
			var susceptibility := str(munitions.get(munition, {}).get("terminal_defense_susceptibility", "Medium"))
			var defense_prob := _terminal_defense_prob(susceptibility, capability, td_config)
			var scored := 0
			for _i in range(count):
				if dice.randf() >= defense_prob:
					scored += 1
			if scored > 0:
				if not hits.has(ship_type):
					hits[ship_type] = {}
				hits[ship_type][munition] = scored
				_add(result["hits_by_munition"], munition, scored)
	return hits


# --- stage 6: damage resolution ------------------------------------------------------------------

const _HULL_FRESH := 0
const _HULL_DAMAGED := 1
const _HULL_SUNK := 2


static func _resolve_damage(
		hits: Dictionary, snaps: Array, crossing_config: Dictionary,
		munitions: Dictionary, dice: Dice, result: Dictionary) -> void:
	var ship_profiles: Dictionary = crossing_config.get("ship_profiles", {})
	var neut_likelihoods: Dictionary = crossing_config.get("neutralization_likelihoods", {})
	var lethality_multipliers: Dictionary = crossing_config.get("lethality_multipliers", {})
	var rehit_multiplier := _cfg_num(crossing_config, "damaged_hull_neut_multiplier", 1.5)
	var surviving_sent: Dictionary = {}
	for snap in snaps:
		surviving_sent[snap["ship_type"]] = int(snap["surviving_sent"])

	# Reconciliation guard: the hits dict and hits_by_munition ledger must agree.
	var hits_dict_total := 0
	for by_m in hits.values():
		hits_dict_total += _sum(by_m)
	assert(hits_dict_total == _sum(result["hits_by_munition"]),
		"crossing pipeline: hits dict and hits_by_munition ledger disagree")

	var ship_keys := hits.keys()
	ship_keys.sort()
	for ship_type in ship_keys:
		var by_munition: Dictionary = hits[ship_type]
		if not surviving_sent.has(ship_type):
			result["warnings"].append(
				"Hit ship type '%s' is absent from ship snapshots; its hits produce no casualties" % ship_type)
			continue
		var capacity := int(surviving_sent[ship_type])
		if capacity <= 0:
			continue
		var vulnerability := str(ship_profiles.get(ship_type, {}).get("vulnerability", "Medium"))
		var base_neut := _cfg_num(neut_likelihoods, vulnerability, 0.0)

		var hulls: Array = []
		for _i in range(capacity):
			hulls.append(_HULL_FRESH)

		# Flatten this ship type's hits into a shuffled munition list (no front-loading).
		var flat: Array = []
		var mun_keys := by_munition.keys()
		mun_keys.sort()
		for munition in mun_keys:
			for _i in range(int(by_munition[munition])):
				flat.append(munition)
		flat = _shuffled(flat, dice)

		for munition in flat:
			var factor := _cfg_num(
				lethality_multipliers, str(munitions.get(munition, {}).get("lethality", "Medium")), 1.0)
			var idx := _randrange(capacity, dice)
			var state: int = hulls[idx]
			if state == _HULL_SUNK:
				_add(result["wasted_hits_by_munition"], munition, 1)
				continue
			var p_neut := base_neut * factor
			if state == _HULL_DAMAGED:
				p_neut *= rehit_multiplier  # damaged hulls are more fragile
			if dice.randf() < minf(1.0, p_neut):
				hulls[idx] = _HULL_SUNK
			elif state == _HULL_FRESH:
				hulls[idx] = _HULL_DAMAGED
			# a damaged hull that survives a re-hit stays damaged

		var destroyed := 0
		var damaged := 0
		for h in hulls:
			if h == _HULL_SUNK:
				destroyed += 1
			elif h == _HULL_DAMAGED:
				damaged += 1
		if destroyed > 0:
			result["destroyed_by_ship_type"][ship_type] = destroyed
		if damaged > 0:
			result["damaged_by_ship_type"][ship_type] = damaged


# --- helpers -------------------------------------------------------------------------------------

static func _new_result() -> Dictionary:
	return {
		"launched_by_munition": {},
		"failed_in_flight_by_munition": {},
		"intercepted_by_munition": {},
		"leakers_by_munition": {},
		"hits_by_munition": {},
		"decoy_hits_by_munition": {},
		"wasted_hits_by_munition": {},
		"destroyed_by_ship_type": {},
		"damaged_by_ship_type": {},
		"warnings": [],
	}


static func _finalize(result: Dictionary) -> Dictionary:
	result["missile_stage_totals"] = {
		"launched": _sum(result["launched_by_munition"]),
		"failed_in_flight": _sum(result["failed_in_flight_by_munition"]),
		"intercepted": _sum(result["intercepted_by_munition"]),
		"leakers": _sum(result["leakers_by_munition"]),
		"hits": _sum(result["hits_by_munition"]),
		"decoy_hits": _sum(result["decoy_hits_by_munition"]),
		"wasted_hits": _sum(result["wasted_hits_by_munition"]),
	}
	result["casualty_totals"] = {
		"destroyed": _sum(result["destroyed_by_ship_type"]),
		"damaged": _sum(result["damaged_by_ship_type"]),
	}
	return result


static func _normalize_snapshots(ship_snapshots: Array) -> Array:
	var snaps: Array = []
	for s in ship_snapshots:
		if s is Dictionary:
			snaps.append({"ship_type": str(s["ship_type"]), "surviving_sent": int(s["surviving_sent"])})
		else:
			snaps.append({"ship_type": str(s.ship_type), "surviving_sent": int(s.surviving_sent)})
	return snaps


static func _add(ledger: Dictionary, key: Variant, amount: int) -> void:
	if amount != 0:
		ledger[key] = int(ledger.get(key, 0)) + amount


static func _cfg_num(mapping: Dictionary, key: Variant, default_value: float) -> float:
	# Numeric lookup that does NOT treat a configured 0 as missing.
	var value: Variant = mapping.get(key)
	return default_value if value == null else float(value)


static func _reachable_tos(
		source_to: int, range_tier: String, active_tos: Array, to_adjacency: Dictionary) -> Dictionary:
	var reachable: Dictionary = {}
	if range_tier == "whole_island":
		for t in active_tos:
			reachable[int(t)] = true
		return reachable
	if range_tier == "neighboring":
		reachable[source_to] = true
		for t in to_adjacency.get(source_to, []):
			reachable[int(t)] = true
		return reachable
	reachable[source_to] = true  # own_to (default)
	return reachable


static func _parse_source_to(location: Variant) -> Variant:
	var text := str(location).strip_edges()
	if "->" in text:
		text = text.split("->")[0].strip_edges()
	if text.is_valid_float():
		return int(float(text))
	return null


static func _shuffled(arr: Array, dice: Dice) -> Array:
	var n := arr.size()
	if n <= 1:
		return arr.duplicate()
	var out: Array = []
	for i in dice.shuffle_indices(n):
		out.append(arr[i])
	return out


static func _choice(arr: Array, dice: Dice) -> Variant:
	return arr[dice.weighted_choice(_ones(arr.size()))]


static func _randrange(n: int, dice: Dice) -> int:
	return dice.weighted_choice(_ones(n))


static func _ones(n: int) -> Array:
	var w: Array = []
	for _i in range(n):
		w.append(1)
	return w


static func _sum(d: Dictionary) -> int:
	var total := 0
	for v in d.values():
		total += int(v)
	return total


# --- validation (fail-loud on broken config) -----------------------------------------------------

static func validate_combat_catalog(catalog: Dictionary) -> void:
	var munitions: Variant = catalog.get("munitions")
	var launchers: Variant = catalog.get("launchers")
	if not (munitions is Dictionary) or (munitions as Dictionary).is_empty():
		_fail("antiship combat catalog: 'munitions' section missing or empty")
	if not (launchers is Dictionary) or (launchers as Dictionary).is_empty():
		_fail("antiship combat catalog: 'launchers' section missing or empty")

	for name in munitions.keys():
		var spec: Dictionary = munitions[name]
		var rate := float(spec.get("in_flight_failure_rate", 0.0))
		if rate < 0.0 or rate > 1.0:
			_fail("antiship combat catalog: munition '%s' in_flight_failure_rate %s outside [0,1]" % [name, rate])
		if float(spec.get("quantity", 0)) < 0.0:
			_fail("antiship combat catalog: munition '%s' has negative quantity" % name)

	for type_id in launchers.keys():
		var spec: Dictionary = launchers[type_id]
		var loadout: Variant = spec.get("missiles")
		if not (loadout is Array) or (loadout as Array).is_empty():
			_fail("antiship combat catalog: launcher '%s' has an empty missile loadout" % type_id)
		for munition in loadout:
			if not munitions.has(munition):
				_fail("antiship combat catalog: launcher '%s' references unknown munition '%s'" % [type_id, munition])
		if int(spec.get("missiles_per_launcher", 0)) <= 0:
			_fail("antiship combat catalog: launcher '%s' missiles_per_launcher must be positive" % type_id)
		var tier := str(spec.get("range_tier", "own_to"))
		if not VALID_RANGE_TIERS.has(tier):
			_fail("antiship combat catalog: launcher '%s' range_tier '%s' invalid" % [type_id, tier])

	var store_groups: Variant = catalog.get("store_groups", {})
	if not (store_groups is Dictionary):
		_fail("antiship combat catalog: 'store_groups' must be a dict when present")
	for group_name in store_groups.keys():
		var group_spec: Variant = store_groups[group_name]
		if not (group_spec is Dictionary):
			_fail("antiship combat catalog: store_group '%s' must be a dict" % group_name)
		var qty: Variant = group_spec.get("quantity")
		if qty == null or float(qty) < 0.0:
			_fail("antiship combat catalog: store_group '%s' needs a non-negative quantity" % group_name)
	for name in munitions.keys():
		var group: Variant = munitions[name].get("store_group")
		if group != null and not store_groups.has(group):
			_fail("antiship combat catalog: munition '%s' references unknown store_group '%s'" % [name, group])


static func validate_crossing_config(config: Dictionary) -> void:
	for key in ["discrimination_probabilities", "terminal_defense", "neutralization_likelihoods",
			"lethality_multipliers", "ship_profiles"]:
		var section: Variant = config.get(key)
		if not (section is Dictionary) or (section as Dictionary).is_empty():
			_fail("antiship crossing config: '%s' section missing or empty" % key)
	if not (config.get("escort_interception", {}) is Dictionary):
		_fail("antiship crossing config: 'escort_interception' must be a dict")
	for escort in config.get("escort_interception", {}).keys():
		var spec: Dictionary = config["escort_interception"][escort]
		if not spec.has("attempts") or not spec.has("success_prob"):
			_fail("antiship crossing config: escort '%s' needs attempts and success_prob" % escort)
	for ship_type in config["ship_profiles"].keys():
		var profile: Dictionary = config["ship_profiles"][ship_type]
		for field_name in ["target_value", "terminal_defense_capability", "vulnerability"]:
			if not profile.has(field_name):
				_fail("antiship crossing config: ship_profile '%s' missing '%s'" % [ship_type, field_name])


static func _fail(message: String) -> void:
	push_error(message)
	assert(false, message)
