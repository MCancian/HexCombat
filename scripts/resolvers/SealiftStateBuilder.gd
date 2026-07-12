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
##   for brigades that embark AFTER the first echelon, as ready amphibious lift frees up. May be [].
## brigades: Dictionary of brigade_id (String) -> Brigade.
## escort_interception: the crossing config's escort_interception map (ship_type ->
##   {sam_loadout, sam_reload_threshold, ...}). Only consulted when reload_enabled.
## reload_enabled: true when the scenario opts into the escort SAM magazine (escort_reload_time_turns
##   > 0). When false the magazine is left EMPTY (unlimited interception, pre-0004 behavior).
static func build(red_followon_reserve: Array, brigades: Dictionary, escort_interception: Dictionary, reload_enabled: bool) -> SealiftState:
	var state := SealiftState.new()
	state.mainland_pool = ShipReserveBuilder.build(red_followon_reserve, brigades)
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
