class_name AntishipSystem
extends Resource

## One Green anti-ship weapon-system container, aggregated per (TO, type). Mirrors TIV
## contracts/antiship.py AntishipSystemEntry plus the (to, type_id) keying the firing plan uses.
## Rows are expanded from defaults/antiship_grouping_spec.json (platform groups → group_sizes ×
## to_assignments), with display name / detectability / ijfs_profile joined from the system catalog.

@export var to_number: int = 0
@export var type_id: int = 0
@export var type_name: String = ""
@export var detectability: String = ""
@export var quantity: int = 0
@export var original_quantity: int = 0
@export var destroyed: int = 0
@export var fired: int = 0
@export var expended: int = 0
@export var destroyed_this_turn: int = 0
@export var suppressed: bool = false
@export var active: bool = false
@export var special: String = ""          # "C2" for command-and-control nodes (not a firing system)
@export var ijfs_profile: Dictionary = {}
