extends Resource
class_name IjfsWriteback

## Cross-phase writeback produced by GameState._compute_ijfs_writeback after the IJFS day(s): the
## CUMULATIVE anti-ship destroyed/suppressed totals (keyed by AntishipCalculator.encode_key), the
## ground maneuver casualties, and SAM destroyed/suppressed counts. Carried in
## GameState.last_ijfs_writeback. Unlike the other phase summaries this has INTERNAL cross-phase
## consumers — _apply_ijfs_maneuver_casualties reads maneuver_casualties, and resolve_antiship_turn
## reads antiship_destroyed_by_type / antiship_suppressed_by_type to attrit/suppress the Green firing
## systems — so a key typo here would silently break the IJFS→casualty/antiship coupling, not just a
## display field (refactor_audit item 9, the riskiest summary). to_dict() is the JSON-serialization
## boundary; its key order and value types mirror the former dict exactly so the golden/observation
## fixtures stay byte-stable. A null last_ijfs_writeback means the IJFS phase has not resolved.

@export var antiship_destroyed_by_type: Dictionary = {}
@export var antiship_suppressed_by_type: Dictionary = {}
@export var maneuver_casualties: Array = []
@export var sam_destroyed: int = 0
@export var sam_suppressed: int = 0


func to_dict() -> Dictionary:
	return {
		"antiship_destroyed_by_type": antiship_destroyed_by_type.duplicate(true),
		"antiship_suppressed_by_type": antiship_suppressed_by_type.duplicate(true),
		"maneuver_casualties": maneuver_casualties.duplicate(true),
		"sam_destroyed": sam_destroyed,
		"sam_suppressed": sam_suppressed,
	}


## Inverse of to_dict(): rebuild a typed writeback from a (possibly modified) dict. Used by the
## sweep/validation tools that snapshot the writeback, tweak one aggregate, and re-inject it to probe
## the IJFS→antiship coupling. Missing keys fall back to the field defaults.
static func from_dict(d: Dictionary) -> IjfsWriteback:
	var wb := IjfsWriteback.new()
	wb.antiship_destroyed_by_type = (d.get("antiship_destroyed_by_type", {}) as Dictionary).duplicate(true)
	wb.antiship_suppressed_by_type = (d.get("antiship_suppressed_by_type", {}) as Dictionary).duplicate(true)
	wb.maneuver_casualties = (d.get("maneuver_casualties", []) as Array).duplicate(true)
	wb.sam_destroyed = int(d.get("sam_destroyed", 0))
	wb.sam_suppressed = int(d.get("sam_suppressed", 0))
	return wb
