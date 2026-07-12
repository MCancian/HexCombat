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
## escort_sam_loadout: Dictionary of escort ship_type (String) -> initial SAM rounds (int). May be {}.
static func build(red_followon_reserve: Array, brigades: Dictionary, escort_sam_loadout: Dictionary) -> SealiftState:
	var state := SealiftState.new()
	state.mainland_pool = ShipReserveBuilder.build(red_followon_reserve, brigades)
	state.cohorts = []
	state.return_pipeline = {}
	var sam: Dictionary = {}
	for ship_type in escort_sam_loadout.keys():
		sam[String(ship_type)] = int(escort_sam_loadout[ship_type])
	state.escort_sam = sam
	assert(state.validate(), "Invalid initial SealiftState")
	return state
