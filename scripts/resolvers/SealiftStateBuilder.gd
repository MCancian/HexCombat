class_name SealiftStateBuilder
extends RefCounted

## Pure builder for GameState.sealift_state (plan 0004): assembles the initial cross-turn sealift
## state at scenario load. The follow-on troop pool reuses ShipReserveBuilder — mainland_pool entries
## have the SAME shape as the first-echelon ship_reserve ({brigade_id, locked_beach, beach_hex,
## offset_bearing, bns:[…]}) — so the pool and the reserve are expanded by identical, already-tested
## code. Cohorts + return pipeline start empty; each escort type's SAM magazine starts at its loadout
## max. No autoload access — the caller passes the scenario follow-on entries, the brigade lookup,
## and the escort SAM loadout in.


## red_followon_reserve: Array of scenario dicts {brigade_id, locked_beach, beach_hex, offset_bearing}
##   for brigades that embark AFTER the first echelon, as ready amphibious lift frees up. When EMPTY,
##   the pool is auto-seeded from the OOB (see resolve_followon_reserve) — the deep mainland force.
## red_ship_reserve: the first-echelon scenario entries; used both to exclude the first wave from the
##   auto-seeded pool and as the beach set the pool is round-robin assigned across.
## brigades: Dictionary of brigade_id (String) -> Brigade.
## escort_interception: the crossing config's escort_interception map (ship_type ->
##   {sam_loadout, sam_reload_threshold, ...}). Only consulted when reload_enabled.
## reload_enabled: true when the scenario opts into the escort SAM magazine (escort_reload_time_turns
##   > 0). When false the magazine is left EMPTY (unlimited interception, pre-0004 behavior).
static func build(red_followon_reserve: Array, red_ship_reserve: Array, brigades: Dictionary, auto_seed: bool, escort_interception: Dictionary, reload_enabled: bool) -> SealiftState:
	var state := SealiftState.new()
	var followon := resolve_followon_reserve(red_followon_reserve, red_ship_reserve, brigades, auto_seed)
	state.mainland_pool = ShipReserveBuilder.build(followon, brigades)
	state.cohorts = []
	state.return_pipeline = {}
	if reload_enabled:
		for ship_type_value in escort_interception.keys():
			var ship_type := String(ship_type_value)
			var cfg: Dictionary = escort_interception[ship_type_value]
			var loadout := int(cfg.get("sam_loadout", 0))
			if loadout <= 0:
				continue
			state.escort_sam[ship_type] = loadout
			state.escort_sam_max[ship_type] = loadout
			state.escort_sam_threshold[ship_type] = int(cfg.get("sam_reload_threshold", 0))
	assert(state.validate(), "Invalid initial SealiftState")
	return state


## Resolve the follow-on echelon entries fed into the mainland pool. An explicit scenario
## red_followon_reserve wins verbatim (curated echelon, e.g. roc_full_defense). Otherwise, ONLY when
## auto_seed is true, the pool is AUTO-SEEDED as the deep mainland force: every RED brigade not in the
## first wave and not already on the map, round-robin assigned across the first-wave beaches. A
## brigade is atomic — it inherits one beach and all its battalions land there. Brigades are walked in
## OOB (insertion) order so the pool order — and thus the crossing order the resolver embarks in — is
## deterministic. The real crossing throttle is amphibious lift capacity (SealiftResolver's
## amphibious-only embark), not pool size, so the pool is intentionally far larger than any single
## turn can carry. auto_seed=false (no explicit echelon) => empty pool: a one-shot assault (the golden
## fixture, minimal scenarios).
static func resolve_followon_reserve(explicit: Array, red_ship_reserve: Array, brigades: Dictionary, auto_seed: bool) -> Array:
	if not explicit.is_empty():
		return explicit
	if not auto_seed or red_ship_reserve.is_empty():
		return []

	var first_wave_ids: Dictionary = {}
	for entry in red_ship_reserve:
		first_wave_ids[String((entry as Dictionary)["brigade_id"])] = true

	var entries: Array = []
	var beach_index := 0
	for brigade_value in brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team != Brigade.Team.RED:
			continue
		if first_wave_ids.has(brigade.id):
			continue
		if brigade.hex_id != "":  # already placed on the map, not a mainland follow-on
			continue
		var beach: Dictionary = red_ship_reserve[beach_index % red_ship_reserve.size()]
		beach_index += 1
		entries.append({
			"brigade_id": brigade.id,
			"locked_beach": int(beach["locked_beach"]),
			"beach_hex": String(beach["beach_hex"]),
			"offset_bearing": float(beach["offset_bearing"]),
		})
	return entries
