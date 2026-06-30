extends RefCounted
class_name TurnEventLog

## Pure, non-invasive derivation of an ordered per-turn event log from state that
## resolve_turn already stored. The "move"/"commit" events read the order buffers,
## which begin_next_turn clears — so build() MUST run while those buffers are still
## populated. play_turn() satisfies this by calling build() immediately after
## resolve_turn() and before any begin_next_turn(); keep that ordering if you move
## the call. Reads GameState only (never GameData) to stay golden-safe.
static func build(state: GameStateType) -> Array[TurnEvent]:
	var events: Array[TurnEvent] = []
	var seq := 0

	if not state.last_ijfs_summary.is_empty():
		events.append(_event(seq, "ijfs", "", "Red", state.last_ijfs_summary))
		seq += 1

	if state.last_antiship_summary != null:
		events.append(_event(seq, "antiship", "", "Green", state.last_antiship_summary.to_dict()))
		seq += 1

	for team in [Brigade.Team.RED, Brigade.Team.GREEN]:
		for order in state.orders_for(team):
			var mo: MoveOrder = order
			events.append(_event(seq, "move", mo.target_hex, _team_str(team), {
				"brigade_id": mo.brigade_id,
				"target_hex": mo.target_hex,
				"mode": mo.mode,
			}))
			seq += 1

	for team in [Brigade.Team.RED, Brigade.Team.GREEN]:
		for c in state.commitments_for(team):
			var co: CommitOrder = c
			events.append(_event(seq, "commit", co.target_hex, _team_str(team), {
				"brigade_id": co.brigade_id,
				"target_hex": co.target_hex,
			}))
			seq += 1

	for summary in state.last_combat_summaries:
		var s: CombatSummary = summary
		events.append(_event(seq, "combat", s.hex_id, "", s.to_dict()))
		seq += 1

	if state.last_frontline_summary != null:
		events.append(_event(seq, "frontline", "", "", state.last_frontline_summary.to_dict()))
		seq += 1

	if state.last_cleanup_summary != null:
		events.append(_event(seq, "cleanup", "", "", state.last_cleanup_summary.to_dict()))
		seq += 1

	return events


static func _event(seq: int, kind: String, hex_id: String, team: String, data: Dictionary) -> TurnEvent:
	var e := TurnEvent.new()
	e.seq = seq
	e.kind = kind
	e.hex_id = hex_id
	e.team = team
	e.data = data.duplicate(true)
	return e


static func _team_str(team: Brigade.Team) -> String:
	if team == Brigade.Team.GREEN:
		return "Green"
	return "Red"
