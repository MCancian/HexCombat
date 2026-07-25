class_name AirAssaultPolicy
extends RefCounted

## Red policy that plays the air insertion path (plan 0032): everything selfplay_default does on the
## ground, PLUS a standing airborne doctrine — seize the nearest port or airbridge Taiwan still
## holds, and failing that widen the lodgement.
##
## The doctrine is deliberate rather than "drop deepest". Two forces shape it:
##   1. A dropped brigade is out of supply until a Red corridor reaches it, so a deep drop into the
##      rear withers. Targets are therefore ranked by nearness to ground Red already holds.
##   2. Offload throughput — the binding constraint on the whole invasion (plan 0006) — is gated on
##      held infrastructure. Seizing a port by air is the one thing the air path can do that the sea
##      path cannot do for itself.
## Ports first, lodgement second is the honest test of "can Red route around the crossing?", not a
## census farm in empty terrain.
##
## Pure decision over the observation; deterministic (all candidate lists are sorted, ties resolve
## by hex id through PolicyGeometry). No engine access.

const RED_TEAM := "Red"

## Infrastructure the observation reports as still Taiwanese — the seizure targets.
const UNSEIZED_STATUS := "taiwanese"


func build_actions(observation: Dictionary) -> Array:
	var actions: Array = SelfPlayPolicy.new().build_actions(observation)
	actions.append_array(air_insert_actions(observation))
	return actions


## The air_insert orders for this turn: one per brigade with lift waiting, each aimed at the best
## available objective. A brigade already ashore is pinned to its own hex (the observation's
## `locked_hex`), which is what the order validator will accept.
static func air_insert_actions(observation: Dictionary) -> Array:
	var air: Dictionary = observation.get("air_insertion", {})
	var eligible: Array = air.get("eligible", [])
	if eligible.is_empty():
		return []

	var red_hexes := _red_held_hexes(observation)
	var objective := _objective_hex(observation, red_hexes)
	if objective.is_empty():
		return []

	var actions: Array = []
	for row_value in eligible:
		var row: Dictionary = row_value
		var locked_hex := String(row.get("locked_hex", ""))
		actions.append({
			"type": "air_insert",
			"team": RED_TEAM,
			"brigade_id": String(row["brigade_id"]),
			"target_hex": objective if locked_hex.is_empty() else locked_hex,
		})
	return actions


## Hexes Red owns, from the observation's occupied-hex list.
static func _red_held_hexes(observation: Dictionary) -> Array:
	var red_hexes: Array = []
	for hex_value in observation.get("occupied_hexes", []):
		var hex_row: Dictionary = hex_value
		if String(hex_row.get("owner", "")) == HexOwner.RED:
			red_hexes.append(String(hex_row["hex_id"]))
	return red_hexes


## Where the next drop goes: the unseized port/airbridge nearest to ground Red holds; failing that,
## a hex adjacent to the lodgement (widening it, and staying in supply). "" when Red holds nothing
## yet — before a beachhead exists there is nowhere a drop could be sustained.
static func _objective_hex(observation: Dictionary, red_hexes: Array) -> String:
	if red_hexes.is_empty():
		return ""

	var unseized: Array = []
	for node_value in observation.get("infrastructure", []):
		var node: Dictionary = node_value
		if String(node.get("status", "")) == UNSEIZED_STATUS:
			unseized.append(String(node["hex"]))
	var port := PolicyGeometry.nearest_hex_by_id(unseized, red_hexes)
	if not port.is_empty():
		return port

	var red_lookup: Dictionary = {}
	for hex_id in red_hexes:
		red_lookup[hex_id] = true
	var fringe: Array = []
	for hex_value in observation.get("occupied_hexes", []):
		var hex_row: Dictionary = hex_value
		if not red_lookup.has(String(hex_row["hex_id"])):
			continue
		for neighbor_value in hex_row.get("neighbors", []):
			var neighbor := String(neighbor_value)
			if not red_lookup.has(neighbor):
				fringe.append(neighbor)
	return PolicyGeometry.nearest_hex_by_id(fringe, red_hexes)
