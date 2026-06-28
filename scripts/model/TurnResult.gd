extends Resource
class_name TurnResult

@export var turn_number: int = 0
@export var contested_hexes: Array[String] = []
@export var combat_summaries: Array = []
@export var ijfs_summary: Dictionary = {}
@export var ijfs_writeback: Dictionary = {}
@export var antiship_summary: Dictionary = {}
@export var frontline_summary: Dictionary = {}
@export var cleanup_summary: Dictionary = {}
@export var events: Array = []

func to_dict() -> Dictionary:
	var events_out: Array = []
	for e in events:
		var te: TurnEvent = e
		events_out.append(te.to_dict())
	return {
		"turn_number": turn_number,
		"contested_hexes": contested_hexes.duplicate(),
		"combat_summaries": combat_summaries.duplicate(true),
		"ijfs_summary": ijfs_summary.duplicate(true),
		"ijfs_writeback": ijfs_writeback.duplicate(true),
		"antiship_summary": antiship_summary.duplicate(true),
		"frontline_summary": frontline_summary.duplicate(true),
		"cleanup_summary": cleanup_summary.duplicate(true),
		"events": events_out,
	}
