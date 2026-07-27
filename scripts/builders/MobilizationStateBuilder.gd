class_name MobilizationStateBuilder
extends RefCounted

## Pure scenario-load builder for the ROC mobilization phase-in (plan 0029 Tier A2). Two steps,
## deliberately split because they run at different moments:
##
##   select_held_back(config, placements, brigades)  — during GameData.load_scenario, BEFORE the
##       placement loop, so the held-back brigades are simply never put on the map.
##   build(config, held_back)                        — at GameState.reset_to_scenario, turning that
##       list into the release schedule MobilizationResolver drains.
##
## No autoload access, no engine state: everything comes in as arguments. Selection and schedule are
## deterministic (brigade_id order) — the mechanic consumes no dice.

const HELD_BACK_KEY := "held_back_brigades"
const DEFAULT_BRIGADE_TYPES: Array[String] = ["reserve"]
const DEFAULT_FIRST_RELEASE_TURN := 4
const DEFAULT_RELEASE_INTERVAL_TURNS := 2
const DEFAULT_BRIGADES_PER_RELEASE := 2

## Every key a green_mobilization block may carry. Anything else is a typo — fail loud rather than
## silently ignoring a knob the researcher believes is live. `_`-prefixed keys are comments.
const KNOWN_KEYS: Array[String] = [
	HELD_BACK_KEY, "brigade_types", "first_release_turn", "release_interval_turns",
	"brigades_per_release",
]


## The scenario placements that start off-map, in release order: [{brigade_id, garrison_hex}].
## Eligible = placed GREEN brigades whose nato_type is in `brigade_types` (default: the OOB's 12
## reserve infantry brigades), taken in brigade_id order. Empty for the default config
## (held_back_brigades = 0) — the pre-0029 laydown, byte for byte.
static func select_held_back(config: Dictionary, placements: Array, brigades: Dictionary) -> Array:
	_validate_keys(config)
	var count := int(config.get(HELD_BACK_KEY, 0))
	if count <= 0:
		return []

	var types: Dictionary = {}
	for type_value in config.get("brigade_types", DEFAULT_BRIGADE_TYPES):
		types[String(type_value).to_lower()] = true

	var eligible: Array = []
	for placement_value in placements:
		var placement: Dictionary = placement_value
		var brigade_id := String(placement.get("brigade_id", ""))
		var brigade: Brigade = brigades.get(brigade_id, null)
		if brigade == null or brigade.team != Brigade.Team.GREEN:
			continue
		if not types.has(brigade.nato_type.to_lower()):
			continue
		eligible.append({"brigade_id": brigade_id, "garrison_hex": String(placement.get("hex", ""))})
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["brigade_id"]) < String(b["brigade_id"]))

	if count > eligible.size():
		push_error("green_mobilization.%s=%d exceeds the %d eligible brigades (types: %s); clamping" % [
			HELD_BACK_KEY, count, eligible.size(), ", ".join(types.keys())])
		count = eligible.size()
	return eligible.slice(0, count)


## Release schedule over the held-back list: `brigades_per_release` brigades arrive on
## `first_release_turn` and every `release_interval_turns` thereafter, in list order.
static func build(config: Dictionary, held_back: Array) -> MobilizationState:
	var state := MobilizationState.new()
	if held_back.is_empty():
		return state

	var first_turn := maxi(1, int(config.get("first_release_turn", DEFAULT_FIRST_RELEASE_TURN)))
	var interval := maxi(1, int(config.get("release_interval_turns", DEFAULT_RELEASE_INTERVAL_TURNS)))
	var per_release := maxi(1, int(config.get("brigades_per_release", DEFAULT_BRIGADES_PER_RELEASE)))

	for index in range(held_back.size()):
		var entry: Dictionary = held_back[index]
		state.pending.append({
			"brigade_id": String(entry["brigade_id"]),
			"garrison_hex": String(entry["garrison_hex"]),
			"release_turn": first_turn + (index / per_release) * interval,
		})
	return state


static func _validate_keys(config: Dictionary) -> void:
	for key_value in config.keys():
		var key := String(key_value)
		if key.begins_with("_") or KNOWN_KEYS.has(key):
			continue
		push_error("Unknown green_mobilization key '%s' (known: %s)" % [key, ", ".join(KNOWN_KEYS)])
