class_name Minefield
extends Resource

## One beach minefield. Static config (num_mines, mines_per_sweeper_per_day) ported from TIV
## defaults/beaches.json Minefield blocks; runtime fields (remaining_mines, dangerous_mines,
## minesweepers_assigned, lane_cleared, ships_destroyed) mirror contracts/antiship.py
## AntishipMinefieldBeachSummary and are mutated by the D3-C mine-warfare resolution.

@export var beach_id: int = 0
@export var name: String = ""
@export var to_number: int = 0
@export var num_mines: int = 0
@export var mines_per_sweeper_per_day: int = 0
@export var remaining_mines: int = 0
@export var dangerous_mines: int = 0
@export var minesweepers_assigned: int = 0
@export var lane_cleared: bool = false
@export var ships_destroyed: int = 0
