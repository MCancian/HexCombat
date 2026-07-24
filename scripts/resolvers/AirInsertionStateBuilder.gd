class_name AirInsertionStateBuilder
extends RefCounted

## Pure scenario-load builder for the air insertion path (plan 0032). Turns a scenario's
## `red_air_insertion` block plus the OOB into the AirInsertionState that AirInsertionResolver
## drains: the pool of battalions waiting to fly and the two per-turn lift budgets.
##
## No autoload access, no engine state — everything arrives as arguments. Pool order is brigade_id
## order, so the observation, the census and any policy see a reproducible queue; the builder
## consumes no dice.
##
## A scenario with NO `red_air_insertion` block (every shipped scenario today) builds an empty
## pool with zero caps: the phase is then a no-op that touches neither state nor the RNG, which is
## what keeps the golden byte-stable while the PLAAF Airborne Corps sits in the OOB.

const DEFAULT_AIRBORNE_CAP := 7
const DEFAULT_AIR_ASSAULT_CAP := 2
const DEFAULT_FIRST_TURN := 1

## Fraction of an inserting packet destroyed when Taiwan's air defences are at FULL health
## (effective_ad_health 1.0). USER call 2026-07-24: an intact system destroys 75% of the lift.
## Applied linearly in AD health, which is what makes a typical post-warmup drop cost ~15-18%
## (measured effective_ad_health after the 3-day IJFS warmup is 0.244 on turn 1).
const DEFAULT_MAX_ATTRITION_AT_FULL_AD := 0.75

## Additional fraction destroyed for ROTARY-WING lift at full MANPADS threat, on top of the AD-health
## term. The shoulder-launched layer is deliberately excluded from AD health (it is not
## SEAD-targetable) yet it is precisely what kills low fliers — so it is the air-assault lift's
## second, separate clock: ~1975 ready launchers on turn 1 saturate the threat, and the layer is
## spent by turn 5.
const DEFAULT_MANPADS_MAX_ATTRITION := 0.25

## Every key a red_air_insertion block may carry. Anything else is a typo — fail loud rather than
## silently ignoring a knob the researcher believes is live. `_`-prefixed keys are comments.
const KNOWN_KEYS: Array[String] = [
	"enabled", "airborne_cap_per_turn", "air_assault_cap_per_turn", "first_turn",
	"max_attrition_at_full_ad", "manpads_max_attrition",
]


## The runtime state. brigades: brigade_id -> Brigade (GameData.brigades). Every Red brigade whose
## OOB nato_type gives it a lift class AND which the scenario has not placed on the map joins the
## pool; a scenario that wants an air brigade to start ashore simply places it, and it is skipped.
static func build(config: Dictionary, brigades: Dictionary) -> AirInsertionState:
	_validate_keys(config)
	var state := AirInsertionState.new()
	if not bool(config.get("enabled", true)) or config.is_empty():
		return state

	state.first_turn = int(config.get("first_turn", DEFAULT_FIRST_TURN))
	state.caps = {
		LiftClass.AIRBORNE: int(config.get("airborne_cap_per_turn", DEFAULT_AIRBORNE_CAP)),
		LiftClass.AIR_ASSAULT: int(config.get("air_assault_cap_per_turn", DEFAULT_AIR_ASSAULT_CAP)),
	}
	state.initial_caps = state.caps.duplicate()

	var brigade_ids: Array[String] = []
	for brigade_id in brigades.keys():
		brigade_ids.append(String(brigade_id))
	brigade_ids.sort()

	for brigade_id in brigade_ids:
		var brigade: Brigade = brigades[brigade_id]
		if brigade.team != Brigade.Team.RED or brigade.hex_id != "":
			continue
		var lift_class := LiftClass.for_brigade(brigade)
		if lift_class == "":
			continue
		state.pool.append({
			"brigade_id": brigade_id,
			"lift_class": lift_class,
			"bns": battalion_manifest(brigade),
		})

	assert(state.validate(), "Invalid initial AirInsertionState")
	return state


## One entry per battalion INSTANCE, `{id, type}`, ids stable and unique within the brigade —
## the same manifest shape ShipReserveBuilder produces for sea lift, so the census and the
## observation can walk an air pool entry and a ship_reserve entry with one code path.
static func battalion_manifest(brigade: Brigade) -> Array:
	var manifest: Array = []
	var index := 0
	for battalion_value in brigade.composition:
		var battalion: Battalion = battalion_value
		for _qty_index in range(battalion.qty):
			index += 1
			manifest.append({"id": "%s-AIR-%d" % [brigade.id, index], "type": battalion.type})
	return manifest


## The attrition coefficients the resolver needs, defaulted. Kept separate from the state because
## they are scenario CONTENT (dialled and swept), not runtime state that evolves during a game.
static func attrition_config(config: Dictionary) -> Dictionary:
	_validate_keys(config)
	return {
		"max_attrition_at_full_ad": float(
			config.get("max_attrition_at_full_ad", DEFAULT_MAX_ATTRITION_AT_FULL_AD)),
		"manpads_max_attrition": float(
			config.get("manpads_max_attrition", DEFAULT_MANPADS_MAX_ATTRITION)),
	}


static func _validate_keys(config: Dictionary) -> void:
	for key_value in config.keys():
		var key := String(key_value)
		if key.begins_with("_") or key in KNOWN_KEYS:
			continue
		push_error("red_air_insertion: unknown key '%s' (known: %s)" % [key, ", ".join(KNOWN_KEYS)])
