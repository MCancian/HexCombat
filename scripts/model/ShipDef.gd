extends Resource
class_name ShipDef

@export var id: int = 0
@export var name: String = ""
@export var display_name: String = ""
@export var category: String = ""
@export var infrastructure: bool = false
@export var total_count: int = 0
@export var initial_ready: int = 0
@export var carrying_capacity_bn_equiv: float = 0.0
@export var is_decoy: bool = false
@export var setup_group: String = ""
@export var mine_neutralization_likelihood: String = ""  # optional per-hull override; "" => use category
@export var area_sam_capacity: int = 0  # number of area-defense SAMs (e.g. HHQ-9, HQ-16) the hull carries

# Ship categories whose carriers may lift the amphibious follow-on echelon. Membership is EXACT — do
# not substring-match on "Amphibious": the category set also contains "Civilian_Non_Amphibious",
# which *contains* that substring, so a `.contains("Amphibious")` test would wrongly admit ordinary
# civilian hulls into amphibious lift.
const AMPHIBIOUS_LIFT_CATEGORIES := ["Military_Amphibious", "Civilian_Amphibious"]


## True when this hull ever sails with a wave. Infrastructure hulls (ports/piers) never sail unless
## flagged as decoys.
func sails() -> bool:
	return is_decoy or not infrastructure


## True when the hull carries battalions; false for escorts and decoys (capacity 0 = the screen).
func is_carrier() -> bool:
	return carrying_capacity_bn_equiv > 0.0


## True when the hull may lift the amphibious follow-on echelon (a carrier in an amphibious category).
func is_amphibious_lift() -> bool:
	return is_carrier() and category in AMPHIBIOUS_LIFT_CATEGORIES
