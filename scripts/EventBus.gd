extends Node
class_name EventBusType

signal hex_selected(hex_id: String)
signal brigade_selected(brigade_id: String)
signal selection_cleared()
signal turn_resolved(turn_number: int)
signal combat_resolved(summaries: Array)
signal phase_changed(phase: int)
signal reachable_hexes_changed(hex_ids: Array)
signal move_mode_changed(mode: String)
signal move_order_issued(brigade_id: String, target_hex: String, mode: String)
signal turn_advanced(turn_number: int)
