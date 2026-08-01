class_name FrontlineResolver
extends RefCounted

## Pure resolver for the D5 front-line phase (refactor_audit item 10, Phase B): maps the drawn
## polyline to a hex sequence (FrontLineService) and redistributes the drawing side's brigades
## evenly along it. Deterministic — consumes no dice; affected ids are sorted before distribution.
## No autoload/engine access — GameState's thin wrapper passes the hex centers + candidate
## brigades in, applies the returned moves via GameData.set_brigade_hex, and owns the
## EventBus.frontline_resolved emit.


## polyline_coords: [[lat, lon], …] drawn front line.
## hex_centers: [{id, lat, lon}, …] flat hex-center records (GameState._frontline_hex_centers()).
## candidate_brigades: the drawing side's live brigades (Red today — TIV's single-side filter;
## the caller owns team selection). Only those whose current hex is on the line reshuffle.
## Returns a FrontlineSummary (empty when the polyline maps to no hexes); the caller applies
## summary.moves — this class moves nothing itself.
static func resolve(polyline_coords: Array, hex_centers: Array, candidate_brigades: Array) -> FrontlineSummary:
	var summary := FrontlineSummary.new()
	var hex_sequence: Array = FrontLineService.find_hexes_for_polyline(polyline_coords, hex_centers)
	if hex_sequence.is_empty():
		return summary

	# Snapshot the affected set BEFORE any movement (no mid-iteration mutation); sort so
	# distribute_units_along_hexes is deterministic.
	var affected_ids: Array[String] = []
	for brigade_value in candidate_brigades:
		var brigade: Brigade = brigade_value
		if brigade.hex_id in hex_sequence:
			affected_ids.append(brigade.id)
	affected_ids.sort()

	summary.hex_sequence = hex_sequence
	summary.affected_brigades = affected_ids
	summary.moves = FrontLineService.distribute_units_along_hexes(affected_ids, hex_sequence)
	return summary
