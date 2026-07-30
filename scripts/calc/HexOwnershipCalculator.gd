class_name HexOwnershipCalculator
extends RefCounted

## Derives hex ownership from brigade occupancy (plan 0047). Pure: it reads the placement index
## through `GameDataStore`'s public queries and returns plain dictionaries. It writes nothing, holds
## no `HexState`, and never repairs the placement index — `MapTransitions` applies what it returns.
##
## THE ABSENCE IS THE RULE, AND IT IS THE WHOLE MECHANIC. A hex with no live brigade is ABSENT from
## both results below, and that absence is what keeps a port Red after Red's garrison moves inland.
## Callers must ITERATE the returned entries. The moment anyone writes
## `owners.get(hex_id, HexOwner.GREEN)` over every hex instead, sticky ownership is gone and every
## seized port un-seizes the turn it is left empty — a silent rewrite of plan 0006's whole
## infrastructure mechanic that no type error would catch.
##
## Brigade PRESENCE decides occupancy, not landed battalion count: a brigade whose battalions are all
## still afloat still holds the ground it stands on. Destroyed brigades hold nothing.


## Occupancy of every hex in `hex_ids` that has at least one live brigade:
## hex_id -> {"red": bool, "green": bool}. A hex with no live brigade is absent from the result.
static func occupancy_from_placements(data_store: GameDataStore, hex_ids: Array) -> Dictionary:
	var occupancy: Dictionary = {}
	for hex_id_value in hex_ids:
		var hex_id := String(hex_id_value)
		var has_red := false
		var has_green := false
		for brigade_id_value in data_store.get_brigades_in_hex(hex_id):
			var brigade: Brigade = data_store.get_brigade(String(brigade_id_value))
			if brigade == null or brigade.destroyed:
				continue
			match brigade.team:
				Brigade.Team.RED:
					has_red = true
				Brigade.Team.GREEN:
					has_green = true
		if has_red or has_green:
			occupancy[hex_id] = {"red": has_red, "green": has_green}
	return occupancy


## occupancy -> {hex_id: HexOwner.*}. Both sides present is CONTESTED. Only occupied hexes appear.
static func owners_from_occupancy(occupancy: Dictionary) -> Dictionary:
	var owners: Dictionary = {}
	for hex_id_value in occupancy.keys():
		var entry: Dictionary = occupancy[hex_id_value]
		var has_red := bool(entry.get("red", false))
		var has_green := bool(entry.get("green", false))
		if has_red and has_green:
			owners[String(hex_id_value)] = HexOwner.CONTESTED
		elif has_red:
			owners[String(hex_id_value)] = HexOwner.RED
		elif has_green:
			owners[String(hex_id_value)] = HexOwner.GREEN
	return owners
