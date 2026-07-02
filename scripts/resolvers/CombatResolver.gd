class_name CombatResolver
extends RefCounted

## Pure resolver for the per-hex ground-combat core (refactor_audit item 10, Phase D): builds the
## maneuver/support forces from the contributor brigades, injects supply effectiveness, runs the
## ported CombatCalculator.resolve_map_attack (the SOLE base-dice-stream consumer in the game),
## and constructs the CombatSummary. It applies NOTHING — casualty application, FEBA
## accumulation, fought flags, ownership, and retreats stay in GameState, because combat at one
## hex mutates state the next hex's contributor gathering reads (the interleaving is part of the
## ported semantics, and application touches GameData indexes).


## Mirrors TIV boots_combat_service._inject_supply_effectiveness: Red maneuver units fight at
## full effectiveness while the Red DOS pool is positive, and at out_of_supply_effectiveness once
## it is exhausted (<= 0). Green has no DOS model, so its effectiveness stays 1.0.
static func inject_supply_effectiveness(units: Array, team: int, red_supply_pool: float, out_of_supply_effectiveness: float) -> void:
	if team != Brigade.Team.RED:
		return
	var eff: float = 1.0 if red_supply_pool > 0.0 else out_of_supply_effectiveness
	if eff == 1.0:
		return
	for unit in units:
		if unit is Dictionary:
			unit["supply_effectiveness"] = eff


static func brigade_ids(brigades: Array) -> Array[String]:
	var ids: Array[String] = []
	for brigade_value in brigades:
		var brigade: Brigade = brigade_value
		ids.append(brigade.id)
	return ids


## Resolve one contested hex. Returns {"result": CombatResult|null, "summary": CombatSummary|null}
## (both null when either side has no contributors — no dice consumed in that case). The summary's
## owner_after is left for the caller (ownership is board state this class never sees).
static func resolve_at(
	hex_id: String,
	attacker_brigades: Array,
	defender_brigades: Array,
	dice: Dice,
	feba_base_km: float,
	red_supply_pool: float,
	red_out_of_supply_effectiveness: float,
) -> Dictionary:
	if attacker_brigades.is_empty() or defender_brigades.is_empty():
		return {"result": null, "summary": null}

	var attacker_units := CombatForces.maneuver_units(attacker_brigades)
	var defender_units := CombatForces.maneuver_units(defender_brigades)
	var attacker_support := CombatForces.support_counts(attacker_brigades)
	var defender_support := CombatForces.support_counts(defender_brigades)
	inject_supply_effectiveness(attacker_units, Brigade.Team.RED, red_supply_pool, red_out_of_supply_effectiveness)
	inject_supply_effectiveness(defender_units, Brigade.Team.GREEN, red_supply_pool, red_out_of_supply_effectiveness)
	var result := CombatCalculator.resolve_map_attack(
		dice,
		attacker_units,
		defender_units,
		attacker_support,
		defender_support,
		1.0,
		feba_base_km
	)

	var summary := CombatSummary.new()
	summary.hex_id = hex_id
	summary.attacker_losses = result.attacker_losses
	summary.defender_losses = result.defender_losses
	summary.feba_movement_km = result.feba_movement_km
	summary.combat_detail = result.combat_detail
	summary.attacker_brigade_ids = brigade_ids(attacker_brigades)
	summary.defender_brigade_ids = brigade_ids(defender_brigades)
	return {"result": result, "summary": summary}
