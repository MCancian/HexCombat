class_name AntishipSystem
extends Resource

## One Green anti-ship weapon-system container, aggregated per (TO, type). Mirrors TIV
## contracts/antiship.py AntishipSystemEntry plus the (to, type_id) keying the firing plan uses.
## Rows are expanded from defaults/antiship_grouping_spec.json (platform groups → group_sizes ×
## to_assignments), with display name / detectability / ijfs_profile joined from the system catalog.
##
## FIELD LIFETIMES (plan 0043). `original_quantity` is the establishment, fixed at construction.
## Losses are kept as two SOURCE-SPECIFIC cumulative campaign totals, because the IJFS bombs
## containers while launch attrition kills deployed launchers — the same arsenal seen twice, so the
## two counts are not comparable and must never be merged into one running total:
##   ijfs_destroyed_cumulative    campaign-cumulative kills reported by the IJFS writeback
##   launch_destroyed_cumulative  campaign-cumulative pre- + post-launch kills, one crossing at a time
## `destroyed` and `quantity` are PROJECTIONS of those three numbers, not independent state:
##   destroyed = mini(ijfs_destroyed_cumulative + launch_destroyed_cumulative, original_quantity)
##   quantity  = original_quantity - destroyed
## The sum is clamped rather than asserted: because the two sources count different projections of
## one arsenal, they can double-count the same physical launcher in a sustained campaign.
##
## Exact ownership — which class may write which field — lives in tools/mutation_authority_manifest.json
## and nowhere else; do not copy it here.

@export var to_number: int = 0
@export var type_id: int = 0
@export var type_name: String = ""
@export var detectability: String = ""
@export var quantity: int = 0
@export var original_quantity: int = 0
@export var ijfs_destroyed_cumulative: int = 0
@export var launch_destroyed_cumulative: int = 0
@export var destroyed: int = 0
## Per-crossing reporting counters, cleared by the end-of-turn reset. `fired` is launchers that got a
## missile away; `destroyed_this_turn` is what the crossing killed; `suppressed_now` is how many
## launchers the current IJFS cycle has pinned — a COUNT, because firing capacity falls in proportion
## to it, and suppression never reduces the surviving establishment. How many attempted and how many
## launched belong to the crossing's report (AntishipLaunchOutcome), not to the arsenal.
@export var fired: int = 0
@export var destroyed_this_turn: int = 0
@export var suppressed_now: int = 0
@export var active: bool = false
@export var special: String = ""          # "C2" for command-and-control nodes (not a firing system)
@export var ijfs_profile: Dictionary = {}


## The two projections this row must always satisfy, as the numbers themselves. The ONE definition
## of the establishment equation: the mutation authority reprojects from it after every campaign
## write, and tools/validate_antiship_data.gd checks freshly built rows against it.
func projected_destroyed() -> int:
	return mini(ijfs_destroyed_cumulative + launch_destroyed_cumulative, original_quantity)


func projected_quantity() -> int:
	return maxi(0, original_quantity - projected_destroyed())


## "" when this row is internally consistent, otherwise the reason it is not. Checks each loss
## SOURCE against the establishment separately (each is individually bounded by it) and the two
## projections against the equation; it deliberately does NOT check their sum, which may exceed the
## establishment by double-counting — see the header.
func establishment_error() -> String:
	if original_quantity < 0:
		return "original_quantity %d is negative" % original_quantity
	if ijfs_destroyed_cumulative < 0 or ijfs_destroyed_cumulative > original_quantity:
		return "ijfs_destroyed_cumulative %d outside 0..%d" % [ijfs_destroyed_cumulative, original_quantity]
	if launch_destroyed_cumulative < 0 or launch_destroyed_cumulative > original_quantity:
		return "launch_destroyed_cumulative %d outside 0..%d" % [launch_destroyed_cumulative, original_quantity]
	if destroyed != projected_destroyed():
		return "destroyed %d != projected %d" % [destroyed, projected_destroyed()]
	if quantity != projected_quantity():
		return "quantity %d != projected %d" % [quantity, projected_quantity()]
	return ""
