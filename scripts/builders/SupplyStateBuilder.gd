class_name SupplyStateBuilder
extends RefCounted

## Pure builder for GameState.supply_state (refactor_audit item 10, Phase A): a fresh Red DOS
## pool from the scenario's starting DOS count. No autoload access — the caller passes
## GameData.red_dos_start in.

const SupplyStateResource = preload("res://scripts/model/SupplyState.gd")


## red_dos_start: scenario starting DOS (days of supply); pool = DOS × TONS_PER_DOS.
static func build(red_dos_start: float) -> SupplyState:
	var supply_state: SupplyState = SupplyStateResource.new()
	supply_state.current_dos_tons = red_dos_start * DosConsumption.TONS_PER_DOS
	supply_state.day_history = []
	return supply_state
