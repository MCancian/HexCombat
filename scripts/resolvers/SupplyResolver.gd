class_name SupplyResolver
extends RefCounted

## Pure resolver for the D2 Red DOS supply phase (refactor_audit item 10, Phase B): computes the
## activity-aware consumption summary and applies it to the passed SupplyState (a plain Resource —
## mutation-in is the contract), appending to its day_history. Consumes NO dice (deterministic).
## No autoload/engine access — GameState's thin wrapper gathers units/activity from GameData and
## owns the EventBus.supply_updated emit.


## units: DosConsumption battalion records ({brigade_id, type, brigade_type} per BN instance).
## moved_ids / engaged_ids: Red brigade ids that moved / fought this turn.
## Returns the consumption summary Dictionary (the public/JSON contract for this phase).
static func resolve(supply_state: SupplyState, units: Array, moved_ids: Array[String], engaged_ids: Array[String], turn_number: int) -> Dictionary:
	var summary := DosConsumption.calculate_consumption(units, moved_ids, engaged_ids, turn_number)
	var pool_before := supply_state.current_dos_tons
	var consumed := float(summary["red_dos_consumed_tons"])
	supply_state.current_dos_tons = maxf(0.0, pool_before - consumed)
	summary["applied"] = true
	summary["pool_before"] = pool_before
	summary["pool_after"] = supply_state.current_dos_tons
	# Combat-effectiveness injection from supply exhaustion happens at the combat call site
	# (GameState._inject_supply_effectiveness), not here.
	supply_state.day_history.append(summary)
	return summary
