class_name MobilizationResolver
extends RefCounted

## Pure resolver for the ROC mobilization phase (plan 0029 Tier A2): each turn, release the Green
## brigades whose mobilization is complete onto the map. Consumes NO dice — release is a schedule,
## not a roll — so a scenario that holds nobody back is byte-identical to the pre-0029 engine.
##
## Purity boundary: this drains MobilizationState and reports what should arrive where; the caller
## (ReinforcementPhases.resolve_mobilization_turn) owns the GameData mutation (set_brigade_hex) and the
## IJFS target append, exactly as OffloadResolver leaves landing application to its wrapper. Live map
## knowledge enters through the `arrival_hex_for` Callable so no autoload is touched here.

## How far from its garrison a displaced brigade will look for somewhere to form up. Six rings is
## generous next to a beachhead's radius: beyond that the sector is gone and waiting a turn (the
## deferred path) is the honest outcome, not teleporting the formation across the island.
const MAX_ARRIVAL_SEARCH_RINGS := 6


## arrival_hex_for: Callable(garrison_hex: String) -> String — the hex the brigade actually forms up
## on, or "" when nowhere suitable is in range (the brigade stays pending and retries next turn).
static func resolve(
	state: MobilizationState, turn_number: int, brigades: Dictionary, arrival_hex_for: Callable
) -> MobilizationSummary:
	var summary := MobilizationSummary.new()
	if state == null:
		return summary

	var still_pending: Array = []
	for entry_value in state.pending:
		var entry: Dictionary = entry_value
		if int(entry["release_turn"]) > turn_number:
			still_pending.append(entry)
			continue

		var brigade_id := String(entry["brigade_id"])
		var brigade: Brigade = brigades.get(brigade_id, null)
		if brigade == null:
			push_error("Mobilization references unknown brigade_id: %s" % brigade_id)
			continue

		var garrison_hex := String(entry["garrison_hex"])
		var arrival_hex := String(arrival_hex_for.call(garrison_hex))
		if arrival_hex.is_empty():
			summary.deferred.append(brigade_id)
			still_pending.append(entry)
			continue

		var battalions := brigade.get_battalion_count()
		var displaced := arrival_hex != garrison_hex
		summary.arrivals.append({
			"brigade_id": brigade_id,
			"hex_id": arrival_hex,
			"battalions": battalions,
			"displaced": displaced,
		})
		summary.battalions_arrived += battalions
		state.released.append({
			"brigade_id": brigade_id,
			"hex_id": arrival_hex,
			"turn": turn_number,
			"displaced": displaced,
		})

	state.pending = still_pending
	summary.pending_brigades = still_pending.size()
	summary.pending_battalions = state.pending_battalions(brigades)
	return summary


## Nearest hex a mobilizing brigade can form up on: its own garrison hex when that is still
## available, else the closest available hex by BFS ring, ties broken by hex id so the choice is
## reproducible. Returns "" when nothing within MAX_ARRIVAL_SEARCH_RINGS qualifies.
## neighbors_of: Callable(hex_id) -> Array[String]; is_available: Callable(hex_id) -> bool.
static func find_arrival_hex(
	garrison_hex: String, neighbors_of: Callable, is_available: Callable,
	max_rings: int = MAX_ARRIVAL_SEARCH_RINGS
) -> String:
	if garrison_hex.is_empty():
		return ""
	if bool(is_available.call(garrison_hex)):
		return garrison_hex

	var visited := {garrison_hex: true}
	var frontier: Array[String] = [garrison_hex]
	for _ring in range(max_rings):
		var next_frontier: Array[String] = []
		for hex_id in frontier:
			for neighbor_value in neighbors_of.call(hex_id):
				var neighbor := String(neighbor_value)
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				next_frontier.append(neighbor)
		next_frontier.sort()
		for hex_id in next_frontier:
			if bool(is_available.call(hex_id)):
				return hex_id
		if next_frontier.is_empty():
			return ""
		frontier = next_frontier
	return ""
