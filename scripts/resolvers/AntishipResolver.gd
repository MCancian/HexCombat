class_name AntishipResolver
extends RefCounted

## Pure resolver for the D3 anti-ship + mine-warfare phase (refactor_audit item 10, Phase C):
## derives the firing percentages from the post-IJFS establishment, builds the firing plan, resolves
## launch attrition, the crossing, and the geometric mine transit, then converts ship losses to
## BNs lost at sea. Receives the ALREADY-DERIVED "antiship:<turn>" substream — it never touches
## the base combat stream.
##
## It writes NO anti-ship state (plan 0043): the IJFS effects have already been applied by
## AntishipTransitions before it is called, and the launch destruction it reports is returned as
## typed AntishipLaunchOutcome rows for the same authority to apply afterwards. Field reassignment
## (ship_reserve, lost_at_sea_accumulator, pending_lost_at_sea, last_antiship_summary) and the
## EventBus emit stay in the FiresPhases coordinator. TO lookups arrive as plain maps so this file
## never reaches for the GameData autoload.
##
## It stays in scripts/resolvers/ rather than moving to scripts/calc/ with the anti-ship calculators
## (plan 0043 step 9) for ONE reason: `remaining_reserve_after_losses` rewrites `entry["bns"]` on the
## caller's live `ship_reserve` entries in place. That is a mixed file by the role-directory rule, and
## it moves when the plan that owns the reserve splits that function out — not before.

## Data sources (single source of truth — used only by this resolver).
const CATALOG_PATH := "res://data/antiship/antiship_combat_catalog.json"
const CROSSING_PATH := "res://data/antiship/antiship_crossing_config.json"
const MINEFIELDS_PATH := "res://data/antiship/minefields.json"

## Default share of each surviving Green launcher group that fires at the crossing each turn.
## 100 = fire-all (maximally lethal). Lethality balance knob — scenario-configurable
## firing/detection percentages are a follow-up (see PLAN.md D3-D).
const DEFAULT_FIRE_PCT := 100.0
## When a TO's C2 node (type 99) is suppressed by the IJFS, the TO loses over-the-horizon
## targeting and its surviving anti-ship systems fire at this fraction of capacity. There is NO
## C2 destruction mechanic — suppression already models the staff knocked out (user call, D3-D).
const C2_SUPPRESSED_FIRE_MULTIPLIER := 0.70


## Returns {"summary": AntishipSummary|null (null = no wave crossing, nothing happened),
## "lost_ids": Array[String], "destroyed_by_type": Dictionary, "bn_equiv_lost": int,
## "accumulator": float}. The caller (GameState) applies hull losses to the sealift cohorts + fleet
## and removes the drowned BNs from the reserve — this pure resolver only computes them (plan 0004 D3).
##
## context.crossing_reserve: the subset of ship_reserve whose BNs actually cross THIS turn (the
## sealift "sent" cohorts), NOT the whole reserve — offloading BNs are safe ashore and are not
## re-attrited. context.sent_by_type is the sailing fleet (cohort carrier hulls + ready escort
## screen) the sealift phase committed this turn; the crossing model attrits exactly these hulls.
static func resolve(turn_number: int, context: AntishipResolutionContext, dice: Dice) -> Dictionary:
	# The crossing wave = BNs sailing this turn (sent cohorts). No wave -> no anti-ship phase.
	var wave := _collect_crossing_wave(context.crossing_reserve)
	var bns_at_sea: Array = wave["bns_at_sea"]
	if bns_at_sea.is_empty():
		return _no_wave_result(context.lost_at_sea_accumulator)

	var target_areas := _target_areas_for(wave["beach_set"], context.beach_to_to)
	var target_beaches: Array = target_areas["beaches"]
	var target_tos: Array = target_areas["tos"]

	var firing := _firing_inputs(context.antiship_systems)

	var crossing_config := AntishipLoaders.load_crossing_config(CROSSING_PATH)
	var combat_catalog := AntishipLoaders.load_combat_catalog(CATALOG_PATH)
	# Magazine gating is left null for this wiring: rebuilt-per-turn it would start full and never
	# bind; meaningful gating needs persistent cross-turn magazine state (follow-up, PLAN.md D3-D).
	var plan := AntishipCalculator.build_firing_plan(
		context.antiship_systems, {}, firing["target_locations"], firing["firing_percentages"], {}, null)
	var attrition := AntishipCalculator.resolve_launch_attrition(
		plan["allocation_plan"], plan["destroyed_firing_plan"],
		crossing_config["launch_attrition"], dice)
	var systems_fired: Array = attrition["systems_fired"]
	_append_off_island_strikes(systems_fired, crossing_config)

	# Sent fleet (D3-D BN<->ship mapping): the sealift phase already committed which hulls sail this
	# turn, so build the crossing snapshots straight from sent_by_type (deterministic ship_type order)
	# instead of re-deriving a minimum-lift fleet here (plan 0004 D3).
	var crossing_context := AntishipCrossingContext.new()
	crossing_context.systems_fired = systems_fired
	crossing_context.ship_snapshots = _snapshots_from_sent(context.sent_by_type)
	crossing_context.combat_catalog = combat_catalog
	crossing_context.crossing_config = crossing_config
	crossing_context.target_tos = target_tos
	crossing_context.active_tos = context.active_tos
	crossing_context.to_adjacency = context.to_adjacency
	crossing_context.escort_sam = context.escort_sam
	var crossing := AntishipCrossing.resolve_crossing_damage(crossing_context, dice)

	var mine_transit := _resolve_mine_transit(
		context.sent_by_type, crossing["destroyed_by_ship_type"], target_beaches, context.ship_defs, dice)
	var destroyed_by_type: Dictionary = mine_transit["destroyed_by_type"]

	# Ship losses -> BNs lost at sea (carry the fractional accumulator across turns). Hull losses are
	# applied to the sealift cohorts + fleet by the caller; this resolver only computes them.
	var losses := ShipLoadingModel.resolve_bn_losses(
		destroyed_by_type, ship_capacity_by_type(context.ship_defs), bns_at_sea,
		context.lost_at_sea_accumulator, dice)

	var summary := AntishipSummary.new()
	summary.resolved_turn = turn_number
	summary.sent_by_type = context.sent_by_type.duplicate(true)
	summary.unliftable_bn = 0
	summary.systems_fired_count = sum_systems_fired(systems_fired)
	summary.destroyed_by_ship_type = destroyed_by_type
	summary.crossing_casualties = crossing["casualty_totals"]
	summary.bns_lost_at_sea = int(losses["bn_equiv_lost"])
	summary.target_beaches = target_beaches
	summary.target_tos = target_tos
	summary.mine_status = mine_status_summary(mine_transit["mine_results"])
	return {
		"summary": summary,
		"lost_ids": losses["lost_ids"],
		"destroyed_by_type": destroyed_by_type,
		"escort_sam_consumed": crossing.get("escort_sam_consumed", {}),
		"launch_outcomes": attrition["outcomes"],
		"bn_equiv_lost": int(losses["bn_equiv_lost"]),
		"accumulator": float(losses["accumulator"]),
	}


## Flatten the sailing reserve entries into the BN wave and the set of locked beaches.
static func _collect_crossing_wave(crossing_reserve: Array) -> Dictionary:
	var bns_at_sea: Array = []
	var beach_set: Dictionary = {}
	for entry in crossing_reserve:
		for bn in entry.get("bns", []):
			bns_at_sea.append(bn)
		beach_set[int(entry.get("locked_beach", 0))] = true
	return {"bns_at_sea": bns_at_sea, "beach_set": beach_set}


## Append OFF-ISLAND firing rows to the on-island firing plan. These model ROC submarines /
## allied air / external ASM: they fire on the crossing wave EVERY turn independent of the
## on-island establishment (no per-TO suppression, no launch attrition),
## and carry no `location`, so AntishipCrossing skips the range gate (whole-strait reach). This is
## the sustained toll the depleting on-island salvo lacks (plan 0028). Default systems_per_turn 0
## => no rows appended => byte-stable. The rows still run the full escort/terminal-defense gauntlet.
static func _append_off_island_strikes(systems_fired: Array, crossing_config: Dictionary) -> void:
	var off_island: Dictionary = crossing_config.get("off_island_strike", {})
	for shooter in off_island.get("shooters", []):
		var launchers := int(shooter.get("systems_per_turn", 0))
		if launchers > 0:
			systems_fired.append({"type": String(shooter.get("type", "")), "systems_fired": launchers})


static func _no_wave_result(lost_at_sea_accumulator: float) -> Dictionary:
	return {
		"summary": null,
		"lost_ids": [],
		"destroyed_by_type": {},
		"escort_sam_consumed": {},
		"launch_outcomes": [],
		"bn_equiv_lost": 0,
		"accumulator": lost_at_sea_accumulator,
	}


## Sorted target beach ids and their TOs. Fail-loud beach->TO lookup against the passed map: an
## unknown beach means the scenario's theater data and its landing sites disagree.
static func _target_areas_for(beach_set: Dictionary, beach_to_to: Dictionary) -> Dictionary:
	var target_beaches: Array = []
	var target_tos: Array = []
	var to_seen: Dictionary = {}
	for beach_id in beach_set.keys():
		if int(beach_id) <= 0:
			continue
		target_beaches.append(int(beach_id))
		var to_number := 0
		if int(beach_id) in beach_to_to:
			to_number = int(beach_to_to[int(beach_id)])
		else:
			push_error("AntishipResolver: unknown beach id %d in beach_to_to" % int(beach_id))
			assert(false)
		if not to_seen.has(to_number):
			to_seen[to_number] = true
			target_tos.append(to_number)
	target_beaches.sort()
	target_tos.sort()
	return {"beaches": target_beaches, "tos": target_tos}


## Derive the firing-plan inputs from the establishment as it stands AFTER AntishipTransitions has
## applied the IJFS effects: destroyed launchers are already gone from `quantity`, and the survivors
## the IJFS has pinned are counted in `suppressed_now` and sit out this crossing. Reads only —
## returns {"firing_percentages": key -> pct, "target_locations": sorted TO numbers}.
static func _firing_inputs(antiship_systems: Array) -> Dictionary:
	# TOs whose C2 (type 99) the IJFS suppressed lose over-the-horizon targeting: every surviving
	# anti-ship system in that TO fires at C2_SUPPRESSED_FIRE_MULTIPLIER of capacity. Computed up
	# front because C2 itself is skipped (continue) in the firing loop below and never fires.
	var c2_suppressed_tos: Dictionary = {}
	for system_value in antiship_systems:
		var c2_system: AntishipSystem = system_value
		if c2_system.type_id != AntishipCalculator.SYSTEM_TYPE_C2:
			continue
		if c2_system.suppressed_now > 0:
			c2_suppressed_tos[c2_system.to_number] = true

	var firing_percentages: Dictionary = {}
	var target_locations: Array = []
	var location_seen: Dictionary = {}
	for system_value in antiship_systems:
		var system: AntishipSystem = system_value
		var key := AntishipCalculator.encode_key(system.to_number, system.type_id)
		if system.type_id == AntishipCalculator.SYSTEM_TYPE_C2:
			continue
		var available := maxi(0, system.quantity)
		if available <= 0:
			continue
		var suppressed := mini(available, system.suppressed_now)
		var fire_pct := DEFAULT_FIRE_PCT * float(available - suppressed) / float(available)
		# C2 suppression stacks on direct per-system suppression: the TO loses targeting entirely.
		if c2_suppressed_tos.has(system.to_number):
			fire_pct *= C2_SUPPRESSED_FIRE_MULTIPLIER
		firing_percentages[key] = fire_pct
		if not location_seen.has(system.to_number):
			location_seen[system.to_number] = true
			target_locations.append(system.to_number)
	target_locations.sort()
	return {"firing_percentages": firing_percentages, "target_locations": target_locations}


## Combine crossing + mine ship losses; mines run on the surviving crossing fleet pool.
## Returns {"destroyed_by_type": ship_type -> hulls lost (crossing + mines),
## "mine_results": per-beach MineWarfareService resolution rows}.
static func _resolve_mine_transit(
	sent_by_type: Dictionary,
	crossing_destroyed: Dictionary,
	target_beaches: Array,
	ship_defs: Dictionary,
	dice: Dice,
) -> Dictionary:
	var destroyed_by_type: Dictionary = {}
	var fleet_pool: Dictionary = sent_by_type.duplicate(true)
	for ship_type in crossing_destroyed.keys():
		destroyed_by_type[ship_type] = int(destroyed_by_type.get(ship_type, 0)) + int(crossing_destroyed[ship_type])
		fleet_pool[ship_type] = maxi(0, int(fleet_pool.get(ship_type, 0)) - int(crossing_destroyed[ship_type]))
	var minefields := AntishipLoaders.load_minefields(MINEFIELDS_PATH)
	var sweepers := AntishipLoaders.available_minesweepers(MINEFIELDS_PATH)
	var mine_config := AntishipLoaders.load_mine_config(MINEFIELDS_PATH)
	var mine_results := MineWarfareService.resolve_ship_losses(
		minefields, target_beaches, distribute_minesweepers(sweepers, target_beaches), fleet_pool,
		dice, mine_ship_meta(ship_defs, mine_config.get("transit", {})), mine_config)
	for beach_result in mine_results:
		for ship_type in (beach_result["ship_loss_counts"] as Dictionary).keys():
			destroyed_by_type[ship_type] = int(destroyed_by_type.get(ship_type, 0)) + int(beach_result["ship_loss_counts"][ship_type])
	return {"destroyed_by_type": destroyed_by_type, "mine_results": mine_results}


## Build crossing snapshots [{ship_type, surviving_sent}] from the sealift-committed sent_by_type,
## in a deterministic ship_type order so the crossing resolution is reproducible.
static func _snapshots_from_sent(sent_by_type: Dictionary) -> Array:
	var types: Array = []
	for ship_type in sent_by_type.keys():
		if int(sent_by_type[ship_type]) > 0:
			types.append(String(ship_type))
	types.sort()
	var snapshots: Array = []
	for ship_type in types:
		snapshots.append({"ship_type": ship_type, "surviving_sent": int(sent_by_type[ship_type])})
	return snapshots


static func ship_capacity_by_type(ship_defs: Dictionary) -> Dictionary:
	var caps: Dictionary = {}
	for ship_def_value in ship_defs.values():
		var ship_def: ShipDef = ship_def_value
		caps[ship_def.name] = ship_def.carrying_capacity_bn_equiv
	return caps


## Remove sunk BNs from the reserve entries (in place) and return the kept entries.
static func remaining_reserve_after_losses(ship_reserve: Array, lost_ids: Array) -> Array:
	if lost_ids.is_empty():
		return ship_reserve
	var lost: Dictionary = {}
	for id in lost_ids:
		lost[String(id)] = true
	var kept: Array = []
	for entry in ship_reserve:
		var bns: Array = entry.get("bns", [])
		var surviving: Array = []
		for bn in bns:
			if not lost.has(String(bn.get("id", ""))):
				surviving.append(bn)
		if surviving.is_empty():
			continue
		entry["bns"] = surviving
		kept.append(entry)
	return kept


## Per-ship-type metadata the geometric mine model needs: decoy flag (sponge ordering), value
## (carrying capacity drives ascending-value transit order), and mine-neutralization likelihood.
## Likelihood precedence: decoy override (minefields.json transit) > per-hull ShipDef
## .mine_neutralization_likelihood (optional, from ships.json) > the transit per-category table.
static func mine_ship_meta(ship_defs: Dictionary, transit_config: Dictionary) -> Dictionary:
	var by_category: Dictionary = transit_config.get("neutralization_likelihood_by_category", {})
	var decoy_label := String(transit_config.get("decoy_neutralization_likelihood", "high"))
	var meta: Dictionary = {}
	for ship_def_value in ship_defs.values():
		var ship_def: ShipDef = ship_def_value
		var label: String
		if ship_def.is_decoy:
			label = decoy_label
		elif ship_def.mine_neutralization_likelihood != "":
			label = ship_def.mine_neutralization_likelihood  # per-hull override
		else:
			label = String(by_category.get(ship_def.category, "high"))  # category fallback
		meta[ship_def.name] = {
			"is_decoy": ship_def.is_decoy,
			"value": ship_def.carrying_capacity_bn_equiv,
			"likelihood": label,
		}
	return meta


## Spread the available minesweepers round-robin across the target beaches (ascending beach_id).
static func distribute_minesweepers(available: int, target_beaches: Array) -> Dictionary:
	var assignments: Dictionary = {}
	if target_beaches.is_empty() or available <= 0:
		return assignments
	var sorted_beaches: Array = target_beaches.duplicate()
	sorted_beaches.sort()
	var i := 0
	while i < available:
		var beach_id := int(sorted_beaches[i % sorted_beaches.size()])
		assignments[beach_id] = int(assignments.get(beach_id, 0)) + 1
		i += 1
	return assignments


static func sum_systems_fired(systems_fired: Array) -> int:
	var total := 0
	for row in systems_fired:
		total += int(row.get("systems_fired", 0))
	return total


static func mine_status_summary(mine_res: Array) -> Array:
	var out: Array = []
	for beach_res in mine_res:
		out.append({
			"beach_id": int(beach_res.get("beach_id", 0)),
			"ships_destroyed": int(beach_res.get("ships_destroyed", 0)),
			"lane_cleared": bool(beach_res.get("lane_cleared", false)),
			"status_color": String(beach_res.get("status_color", "")),
		})
	return out
