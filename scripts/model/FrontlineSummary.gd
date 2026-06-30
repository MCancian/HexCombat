extends Resource
class_name FrontlineSummary

## Result of GameState.resolve_frontline_phase — the polyline's hex sequence, the Red brigades it
## reshuffled, and their new hex assignments. Carried in GameState.last_frontline_summary / TurnResult
## / the event log / the EventBus.frontline_resolved signal. Replaces the former plain dict
## (refactor_audit item 9 — typed drift-safety). to_dict() is the JSON-serialization boundary; its key
## order and value types mirror the former dict exactly so the golden/observation fixtures stay
## byte-stable. A null last_frontline_summary means the phase has not resolved this turn.

@export var hex_sequence: Array = []
@export var affected_brigades: Array[String] = []
@export var moves: Dictionary = {}  # brigade_id (String) -> hex_id (String)


func to_dict() -> Dictionary:
	return {
		"hex_sequence": hex_sequence.duplicate(),
		"affected_brigades": affected_brigades.duplicate(),
		"moves": moves.duplicate(true),
	}
