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
##
## isolated_brigade_ids (plan 0032) overrides that per brigade: an air-landed formation with no Red
## corridor back to a lodgement fights out of supply no matter how full the theatre pool is — the
## DOS tonnage exists, it just cannot reach a battalion behind enemy lines. Empty (the default) is
## the pre-0032 behaviour exactly.
static func inject_supply_effectiveness(
	units: Array, team: int, red_supply_pool: float, out_of_supply_effectiveness: float,
	isolated_brigade_ids: Dictionary = {}
) -> void:
	if team != Brigade.Team.RED:
		return
	var pool_effectiveness: float = 1.0 if red_supply_pool > 0.0 else out_of_supply_effectiveness
	if pool_effectiveness == 1.0 and isolated_brigade_ids.is_empty():
		return
	for unit in units:
		if not (unit is Dictionary):
			continue
		var eff := pool_effectiveness
		if isolated_brigade_ids.has(String(unit.get("brigade_id", ""))):
			eff = out_of_supply_effectiveness
		if eff != 1.0:
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
	rules: CombatRules
) -> Dictionary:
	if attacker_brigades.is_empty() or defender_brigades.is_empty():
		return {"result": null, "summary": null}

	# Only battalions actually ashore fight (plan 0037): a brigade counts as present from its first
	# landed battalion, but the rest of its composition may still be at sea, on the mainland, or
	# waiting to fly. One map serves both sides — Green simply has no entries in it.
	var not_ashore: Dictionary = rules.not_ashore_by_type
	var attacker_units := CombatForces.maneuver_units(attacker_brigades, not_ashore)
	var defender_units := CombatForces.maneuver_units(defender_brigades, not_ashore)
	var attacker_support_units := CombatForces.support_units(attacker_brigades, not_ashore)
	var defender_support_units := CombatForces.support_units(defender_brigades, not_ashore)
	var attacker_support := CombatForces.support_counts(attacker_brigades, not_ashore)
	var defender_support := CombatForces.support_counts(defender_brigades, not_ashore)
	# Only the attacker is injected: this resolver's attacker is always RED and its defender always
	# GREEN (see the header), and Green has no DOS model, so the two defender-side calls this used to
	# make returned immediately by construction. If the attacker/defender roles are ever generalised,
	# supply injection has to be keyed on each side's actual team.
	inject_supply_effectiveness(attacker_units, Brigade.Team.RED, rules.red_supply_pool, rules.red_out_of_supply_effectiveness, rules.isolated_red_brigade_ids)
	inject_supply_effectiveness(attacker_support_units, Brigade.Team.RED, rules.red_supply_pool, rules.red_out_of_supply_effectiveness, rules.isolated_red_brigade_ids)
	var result := CombatCalculator.resolve_map_attack(
		dice,
		attacker_units,
		defender_units,
		attacker_support,
		defender_support,
		attacker_support_units,
		defender_support_units,
		rules
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
