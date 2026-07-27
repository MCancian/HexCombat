class_name FrontlinePhase
extends RefCounted

static func frontline_hex_centers() -> Array:
	var centers: Array = []
	for hex_value in GameData.hexes:
		var hex: Hex = hex_value
		centers.append({"id": hex.id, "lat": hex.center.x, "lon": hex.center.y})
	return centers

static func resolve_frontline_phase(state: GameStateData, polyline_coords: Array) -> Dictionary:
	var candidate_brigades: Array = []
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.RED and not brigade.destroyed:
			candidate_brigades.append(brigade)

	state.last_frontline_summary = FrontlineResolver.resolve(polyline_coords, frontline_hex_centers(), candidate_brigades)
	for brigade_id in state.last_frontline_summary.moves.keys():
		GameData.set_brigade_hex(String(brigade_id), String(state.last_frontline_summary.moves[brigade_id]))
	EventBus.frontline_resolved.emit(state.last_frontline_summary.to_dict())
	return state.last_frontline_summary.to_dict()
