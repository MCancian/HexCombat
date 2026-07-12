class_name AntishipResolver
extends RefCounted

## Pure resolver for the D3 anti-ship + mine-warfare phase (refactor_audit item 10, Phase C):
## applies the IJFS writeback to the Green firing systems, builds the firing plan, resolves
## launch attrition, the crossing, and the geometric mine transit, then converts ship losses to
## BNs lost at sea. Receives the ALREADY-DERIVED "antiship:<turn>" substream — it never touches
## the base combat stream. Mutations inside are the sanctioned Resource kind (AntishipSystem
## quantity/destroyed, fleet ShipStates, ship_reserve entry "bns"); field reassignment
## (ship_reserve, lost_at_sea_accumulator, pending_lost_at_sea, last_antiship_summary) and the
## EventBus emit stay in GameState's wrapper. TO lookups arrive as plain maps because Theaters
## reads the GameData autoload internally.

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
## crossing_reserve: the subset of ship_reserve whose BNs actually cross THIS turn (the sealift
## "sent" cohorts), NOT the whole reserve — offloading BNs are safe ashore and are not re-attrited.
## sent_by_type: the sailing fleet (cohort carrier hulls + ready escort screen) the sealift phase
## committed this turn; the crossing model runs attrition against exactly these hulls.
static func resolve(
	turn_number: int,
	crossing_reserve: Array,
	antiship_systems: Array,
	writeback: IjfsWriteback,
	sent_by_type: Dictionary,
	ship_defs: Dictionary,
	beach_to_to: Dictionary,
	active_tos: Array,
	to_adjacency: Dictionary,
	lost_at_sea_accumulator: float,
	dice: Dice,
) -> Dictionary:
	# The crossing wave = BNs sailing this turn (sent cohorts). No wave -> no anti-ship phase.
	var bns_at_sea: Array = []
	var beach_set: Dictionary = {}
	for entry in crossing_reserve:
		for bn in entry.get("bns", []):
			bns_at_sea.append(bn)
		beach_set[int(entry.get("locked_beach", 0))] = true
	if bns_at_sea.is_empty():
		return {
			"summary": null,
			"lost_ids": [],
			"destroyed_by_type": {},
			"bn_equiv_lost": 0,
			"accumulator": lost_at_sea_accumulator,
		}

	var target_beaches: Array = []
	var target_tos: Array = []
	var to_seen: Dictionary = {}
	for beach_id in beach_set.keys():
		if int(beach_id) <= 0:
			continue
		target_beaches.append(int(beach_id))
		# Fail-loud beach->TO lookup (mirrors Theaters.to_for_beach against the passed map).
		var to_num := 0
		if int(beach_id) in beach_to_to:
			to_num = int(beach_to_to[int(beach_id)])
		else:
			push_error("AntishipResolver: unknown beach id %d in beach_to_to" % int(beach_id))
			assert(false)
		if not to_seen.has(to_num):
			to_seen[to_num] = true
			target_tos.append(to_num)
	target_beaches.sort()
	target_tos.sort()

	# Apply the IJFS writeback to the Green firing systems: destroyed launchers are permanently
	# removed from quantity; suppressed launchers sit out this turn (reduced firing %).
	var ijfs_destroyed: Dictionary = writeback.antiship_destroyed_by_type if writeback != null else {}
	var ijfs_suppressed: Dictionary = writeback.antiship_suppressed_by_type if writeback != null else {}
	# TOs whose C2 (type 99) the IJFS suppressed lose over-the-horizon targeting: every surviving
	# anti-ship system in that TO fires at C2_SUPPRESSED_FIRE_MULTIPLIER of capacity. Computed up
	# front because C2 itself is skipped (continue) in the firing loop below and never fires.
	var c2_suppressed_tos: Dictionary = {}
	for system_value in antiship_systems:
		var c2_system: AntishipSystem = system_value
		if c2_system.type_id != AntishipCalculator.SYSTEM_TYPE_C2:
			continue
		var c2_key := AntishipCalculator.encode_key(c2_system.to_number, c2_system.type_id)
		if int(ijfs_suppressed.get(c2_key, 0)) > 0:
			c2_suppressed_tos[c2_system.to_number] = true
	var firing_percentages: Dictionary = {}
	var target_locations: Array = []
	var loc_seen: Dictionary = {}
	for system_value in antiship_systems:
		var system: AntishipSystem = system_value
		var key := AntishipCalculator.encode_key(system.to_number, system.type_id)
		# `killed` is the CUMULATIVE total destroyed across all IJFS days (see IjfsResolver
		# writeback invariant), so set quantity from original_quantity - idempotent across turns.
		var killed := int(ijfs_destroyed.get(key, 0))
		system.quantity = maxi(0, system.original_quantity - killed)
		system.destroyed = killed
		if system.type_id == AntishipCalculator.SYSTEM_TYPE_C2:
			continue
		var avail := maxi(0, system.quantity)
		if avail <= 0:
			continue
		var suppressed := mini(avail, int(ijfs_suppressed.get(key, 0)))
		var fire_pct := DEFAULT_FIRE_PCT * float(avail - suppressed) / float(avail)
		# C2 suppression stacks on direct per-system suppression: the TO loses targeting entirely.
		if c2_suppressed_tos.has(system.to_number):
			fire_pct *= C2_SUPPRESSED_FIRE_MULTIPLIER
		firing_percentages[key] = fire_pct
		if not loc_seen.has(system.to_number):
			loc_seen[system.to_number] = true
			target_locations.append(system.to_number)
	target_locations.sort()

	var crossing_config := AntishipLoaders.load_crossing_config(CROSSING_PATH)
	var combat_catalog := AntishipLoaders.load_combat_catalog(CATALOG_PATH)
	# Magazine gating is left null for this wiring: rebuilt-per-turn it would start full and never
	# bind; meaningful gating needs persistent cross-turn magazine state (follow-up, PLAN.md D3-D).
	var plan := AntishipCalculator.build_firing_plan(
		antiship_systems, {}, target_locations, firing_percentages, {}, null)
	var attrition := AntishipCalculator.resolve_launch_attrition(
		antiship_systems, plan["allocation_plan"], plan["destroyed_firing_plan"],
		crossing_config["launch_attrition"], dice)
	var systems_fired: Array = attrition["systems_fired"]

	# Sent fleet (D3-D BN<->ship mapping): the sealift phase already committed which hulls sail this
	# turn, so build the crossing snapshots straight from sent_by_type (deterministic ship_type order)
	# instead of re-deriving a minimum-lift fleet here (plan 0004 D3).
	var snapshots := _snapshots_from_sent(sent_by_type)
	var crossing := AntishipCrossing.resolve_crossing_damage(
		systems_fired, snapshots, combat_catalog, crossing_config,
		target_tos, dice, active_tos, to_adjacency)

	# Combine crossing + mine ship losses; mines run on the surviving crossing fleet pool.
	var destroyed_by_type: Dictionary = {}
	var crossing_destroyed: Dictionary = crossing["destroyed_by_ship_type"]
	var fleet_pool: Dictionary = sent_by_type.duplicate(true)
	for t in crossing_destroyed.keys():
		destroyed_by_type[t] = int(destroyed_by_type.get(t, 0)) + int(crossing_destroyed[t])
		fleet_pool[t] = maxi(0, int(fleet_pool.get(t, 0)) - int(crossing_destroyed[t]))
	var minefields := AntishipLoaders.load_minefields(MINEFIELDS_PATH)
	var sweepers := AntishipLoaders.available_minesweepers(MINEFIELDS_PATH)
	var mine_config := AntishipLoaders.load_mine_config(MINEFIELDS_PATH)
	var mine_res := MineWarfareService.resolve_ship_losses(
		minefields, target_beaches, distribute_minesweepers(sweepers, target_beaches), fleet_pool,
		dice, mine_ship_meta(ship_defs, mine_config.get("transit", {})), mine_config)
	for beach_res in mine_res:
		for t in (beach_res["ship_loss_counts"] as Dictionary).keys():
			destroyed_by_type[t] = int(destroyed_by_type.get(t, 0)) + int(beach_res["ship_loss_counts"][t])

	# Ship losses -> BNs lost at sea (carry the fractional accumulator across turns). Hull losses are
	# applied to the sealift cohorts + fleet by the caller; this resolver only reports them.
	var losses := ShipLoadingModel.resolve_bn_losses(
		destroyed_by_type, ship_capacity_by_type(ship_defs), bns_at_sea, lost_at_sea_accumulator, dice)

	var summary := AntishipSummary.new()
	summary.resolved_turn = turn_number
	summary.sent_by_type = sent_by_type.duplicate(true)
	summary.unliftable_bn = 0
	summary.systems_fired_count = sum_systems_fired(systems_fired)
	summary.destroyed_by_ship_type = destroyed_by_type
	summary.crossing_casualties = crossing["casualty_totals"]
	summary.bns_lost_at_sea = int(losses["bn_equiv_lost"])
	summary.target_beaches = target_beaches
	summary.target_tos = target_tos
	summary.mine_status = mine_status_summary(mine_res)
	return {
		"summary": summary,
		"lost_ids": losses["lost_ids"],
		"destroyed_by_type": destroyed_by_type,
		"bn_equiv_lost": int(losses["bn_equiv_lost"]),
		"accumulator": float(losses["accumulator"]),
	}


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
