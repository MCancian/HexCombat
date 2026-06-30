extends Resource
class_name HexState

## Per-hex runtime ownership + front-line state, keyed by hex_id in GameData.hex_states.
## Replaces the former plain {owner, feba_km} dict (refactor_audit item 3 — typed drift-safety).
## owner is a HexOwner.* string constant; feba_km is the signed FEBA displacement (Red-positive).

@export var owner: String = HexOwner.GREEN
@export var feba_km: float = 0.0


func to_dict() -> Dictionary:
	return {
		"owner": owner,
		"feba_km": feba_km,
	}
