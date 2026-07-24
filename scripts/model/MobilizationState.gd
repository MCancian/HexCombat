extends Resource
class_name MobilizationState

## Cross-turn ROC mobilization state (plan 0029 Tier A2, USER call 2026-07-24 — model (b)).
## A slice of the EXISTING Green force starts off-map "in mobilization" instead of standing on its
## garrison hex at H-hour, and phases in over the opening turns. Nothing is invented: the eligible
## brigades are the OOB's own `nato_type: "reserve"` formations, which the pre-0029 laydown assumed
## were manned, equipped and deployed on D-Day.
##
## An off-map brigade is `hex_id == ""` — the same "not present" state Red's at-sea brigades already
## use — so the victory census, IJFS maneuver targeting, legal moves and the LLM observation all
## exclude it with no special-casing. That is the mechanic's lever: held-back battalions sit out the
## front-loaded fires campaign and arrive intact.
##
## Built by MobilizationStateBuilder at scenario load, advanced by MobilizationResolver once per turn
## (between amphibious offload and movement). Carries no RNG — release is a pure schedule.
## to_dict() is the JSON-serialization boundary; its key order and value types are the contract.

## Brigades still mobilizing, in release order. Each entry:
##   {brigade_id: String, garrison_hex: String, release_turn: int}
## garrison_hex is the placement the scenario gave the brigade — where it arrives unless that hex is
## enemy-held at release. Sorted by (release_turn, brigade_id) at build; the resolver drains it.
@export var pending: Array = []

## Arrival log, append-only, in arrival order. Each entry:
##   {brigade_id: String, hex_id: String, turn: int, displaced: bool}
## displaced = the garrison hex was RED/CONTESTED and the brigade fell back to a nearby hex.
@export var released: Array = []


## Battalions still off-map, summed over the pending brigades. brigades: GameData.brigades.
func pending_battalions(brigades: Dictionary) -> int:
	var total := 0
	for entry_value in pending:
		var entry: Dictionary = entry_value
		var brigade: Brigade = brigades.get(String(entry["brigade_id"]), null)
		if brigade != null:
			total += brigade.get_battalion_count()
	return total


func to_dict() -> Dictionary:
	return {
		"pending": pending.duplicate(true),
		"released": released.duplicate(true),
	}
