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

func to_dict() -> Dictionary:
	return {
		"turn_number": turn_number,
		"contested_hexes": contested_hexes.duplicate(),
		"combat_summaries": combat_summaries.duplicate(true),
		"ijfs_summary": ijfs_summary.duplicate(true),
		"ijfs_writeback": ijfs_writeback.duplicate(true),
		"antiship_summary": antiship_summary.duplicate(true),
		"frontline_summary": frontline_summary.duplicate(true),
		"cleanup_summary": cleanup_summary.duplicate(true),
	}
