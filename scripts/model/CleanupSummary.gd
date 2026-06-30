extends Resource
class_name CleanupSummary

## Result of GameState.resolve_cleanup_phase — the end-of-turn system reset count plus the victory
## census/verdict. Carried in GameState.last_cleanup_summary / TurnResult / the event log / the
## EventBus.cleanup_resolved signal. Replaces the former plain dict (refactor_audit item 9 — typed
## drift-safety). to_dict() is the JSON-serialization boundary; its key order and value types mirror
## the former dict exactly so the golden/observation fixtures stay byte-stable. A null
## last_cleanup_summary means the phase has not resolved this turn.

@export var antiship_systems_reset: int = 0
@export var china_battalions_on_taiwan: int = 0
@export var taiwan_battalions_on_taiwan: int = 0
@export var game_over: bool = false
@export var winner: String = ""  # ""/"red"/"green"
@export var victory_reason: String = ""


func to_dict() -> Dictionary:
	return {
		"antiship_systems_reset": antiship_systems_reset,
		"china_battalions_on_taiwan": china_battalions_on_taiwan,
		"taiwan_battalions_on_taiwan": taiwan_battalions_on_taiwan,
		"game_over": game_over,
		"winner": winner,
		"victory_reason": victory_reason,
	}
