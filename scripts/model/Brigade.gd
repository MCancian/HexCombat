extends Resource
class_name Brigade

enum Team { RED, GREEN }


## Canonical display name for a team enum. Sole owner of the capitalized
## "Red"/"Green" mapping — do NOT reimplement locally (see plan 0019). Note the
## lowercase "red"/"green" used in game-record serialization is a DISTINCT mapping.
static func team_name(team: Team) -> String:
	return "Green" if team == Team.GREEN else "Red"


## Inverse of team_name: parses a team display string (case-insensitive) to the enum.
## Silent RED default for any non-"green" input (empty/unknown included) — callers that
## must reject unknown values validate before delegating (see LLMGameAPI._parse_team_string).
static func team_from_name(name: String) -> Team:
	return Team.GREEN if name.to_lower() == TEAM_KEY_GREEN else Team.RED


## Lowercase team tokens for the serialized game-record wire format — the `winner` field and
## the team-keyed census / policy / aggregation dicts. This is a DISTINCT mapping from the
## capitalized display strings above (team_name) and from HexOwner's hex-ownership vocabulary
## (plan 0020, Option 2: two homes kept distinct — outcome/record token vs. ownership value,
## even though the spelling coincides). Sole GDScript home for these tokens; the Python report
## tools read the same JSON contract with their own literals (a language boundary).
const TEAM_KEY_RED := "red"
const TEAM_KEY_GREEN := "green"

# Organization costs (percentage points). Tracked now; inert until wired into combat later.
const MAX_ORGANIZATION := 100.0
const ADMIN_MOVE_ORG_COST := 100.0      # administrative move: -100%
const TACTICAL_MOVE_ORG_COST := 25.0    # tactical move: -25%
const COMBAT_ORG_COST_PER_TURN := 10.0  # -10% per turn in combat
const ORG_RECOVERY_PER_TURN := 10.0     # +10% per turn when neither moving nor fighting

@export var id: String = ""
@export var name: String = ""
@export var team: Team = Team.RED
@export var to_number: int = 0  # theater of operations (TO) the brigade belongs to, from the OOB
@export var nato_type: String = ""
@export var composition: Array[Battalion] = []

@export var hex_id: String = ""
@export var entry_bearing: float = 0.0
@export var moved_this_turn: bool = false
@export var moved_admin_this_turn: bool = false
@export var fought_this_turn: bool = false
# Prior-turn activity (latched in cleanup before the per-turn flags reset). Feeds IJFS detection
# posture: recently-active units are more detectable. See PLAN.md Decisions 2026-06-28 (D4-H Option B).
@export var moved_last_turn: bool = false
@export var fought_last_turn: bool = false
@export var destroyed: bool = false
@export var organization: float = MAX_ORGANIZATION  # 0-100; does not affect combat yet


func get_battalion_count() -> int:
	var total := 0
	for battalion in composition:
		total += battalion.qty
	return total


func to_combat_units() -> Array:
	var units: Array = []
	for battalion in composition:
		for i in range(battalion.qty):
			units.append({
				"brigade_id": id,
				"type": battalion.type,
				"supply_effectiveness": 1.0
			})
	return units


func adjust_organization(delta: float) -> void:
	organization = clampf(organization + delta, 0.0, MAX_ORGANIZATION)
