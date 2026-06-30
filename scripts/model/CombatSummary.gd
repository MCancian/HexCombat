extends Resource
class_name CombatSummary

## Per-contested-hex result of one resolved combat, produced by GameState._resolve_combat_at and
## carried in GameState.last_combat_summaries / TurnResult / the event log / the LLM observation.
## Replaces the former plain dict (refactor_audit item 3 — typed drift-safety). to_dict() is the
## JSON-serialization boundary; its key order and value types mirror the former dict exactly so the
## golden/observation fixtures stay byte-stable.

@export var hex_id: String = ""
@export var attacker_losses: int = 0
@export var defender_losses: int = 0
@export var feba_movement_km: float = 0.0
@export var owner_after: String = ""
@export var combat_detail: Dictionary = {}
@export var attacker_brigade_ids: Array[String] = []
@export var defender_brigade_ids: Array[String] = []


func to_dict() -> Dictionary:
	return {
		"hex_id": hex_id,
		"attacker_losses": attacker_losses,
		"defender_losses": defender_losses,
		"feba_movement_km": feba_movement_km,
		"owner_after": owner_after,
		"combat_detail": combat_detail.duplicate(true),
		"attacker_brigade_ids": attacker_brigade_ids.duplicate(),
		"defender_brigade_ids": defender_brigade_ids.duplicate(),
	}
