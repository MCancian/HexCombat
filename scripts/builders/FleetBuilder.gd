class_name FleetBuilder
extends RefCounted

## Pure builder for GameState.fleet (refactor_audit item 10, Phase A): one fresh ShipState per
## ship definition, all hulls ready, nothing sent/lost. No autoload access — the caller passes
## GameData.ship_defs in.
##
## This is the only place outside `SealiftTransitions` that writes a `ShipState` field, and it is
## registered as a construction writer in tools/mutation_authority_manifest.json: the rows it fills are
## FRESH and unpublished — nothing holds them until `build()` returns. Replacing a LIVE fleet (scenario
## reset) is a different operation and goes through `SealiftTransitions.rebuild_fleet`.

const ShipStateResource = preload("res://scripts/model/ShipState.gd")


## ship_defs: Dictionary of ship name (String) -> ShipDef.
## Returns Dictionary of ship name (String) -> ShipState.
static func build(ship_defs: Dictionary) -> Dictionary:
	var fleet: Dictionary = {}
	for ship_def_value in ship_defs.values():
		var ship_def: ShipDef = ship_def_value
		var ship_state: ShipState = ShipStateResource.new()
		ship_state.ship_type = ship_def.name
		ship_state.fleet_total = ship_def.total_count
		ship_state.fleet_surviving_total = ship_def.total_count
		ship_state.ready = ship_def.total_count
		ship_state.surviving_sent = 0
		ship_state.offloading = 0
		ship_state.returning = 0
		ship_state.destroyed = 0
		assert(ship_state.validate(), "Invalid initial ShipState for %s" % ship_def.name)
		fleet[ship_def.name] = ship_state
	return fleet
