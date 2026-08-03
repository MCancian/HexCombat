extends Resource
class_name FrontlineSummary

## Result of GameState.resolve_frontline_phase — the polyline's hex sequence, the Red brigades it
## reshuffled, and their new hex assignments. Carried in GameState.last_frontline_summary / TurnResult
## / the event log / the EventBus.frontline_resolved signal. Replaces the former plain dict
## (refactor_audit item 9 — typed drift-safety). to_dict() is the JSON-serialization boundary; its key
## order and value types mirror the former dict exactly. pinned by: tools/validate_llm_api.gd (deep
## drift check) — the pin covers the turn_result `frontline_summary` key, but this scenario never
## resolves the frontline phase, so the model's fields are NOT exercised by the fixture (a null
## summary serializes as {}). A null last_frontline_summary means the phase has not resolved this turn.

@export var hex_sequence: Array = []
@export var affected_brigades: Array[String] = []
@export var moves: Dictionary = {}  # brigade_id (String) -> hex_id (String)


func to_dict() -> Dictionary:
	return {
		"hex_sequence": hex_sequence.duplicate(),
		"affected_brigades": affected_brigades.duplicate(),
		"moves": moves.duplicate(true),
	}
