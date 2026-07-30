class_name GameStateBuilder
extends RefCounted

## Static scenario-load builders for GameState's typed sub-state (plan 0014 P2). Each method takes
## explicit GameData-sourced values (never the GameData or GameState autoload itself) and returns
## the built typed object; GameState.gd's `_rebuild_*` wrappers assign the result onto `data`. This
## is the seam that keeps GameState.gd's dependency count down: the per-type builders
## (ShipReserveBuilder, SealiftStateBuilder, FleetBuilder, SupplyStateBuilder,
## InfrastructureStateBuilder, IjfsStateBuilder) are consumed here instead. The anti-ship arsenal is
## the exception: it is built by its mutation authority (AntishipTransitions), not from here.


static func build_ship_reserve(red_ship_reserve: Array, brigades: Dictionary) -> Array:
	return ShipReserveBuilder.build(red_ship_reserve, brigades)


## Escort SAM magazine is seeded from the crossing config only when the scenario opts in via
## escort_reload_turns > 0 (plan 0004 D5); otherwise it stays unmodelled (empty).
static func build_sealift_state(
	red_followon_reserve: Array, red_ship_reserve: Array, brigades: Dictionary,
	auto_seed_followon_pool: bool, escort_reload_turns: int
) -> SealiftState:
	var crossing_config := AntishipLoaders.load_crossing_config(AntishipResolver.CROSSING_PATH)
	var escort_interception: Dictionary = crossing_config.get("escort_interception", {})
	return SealiftStateBuilder.build(
		red_followon_reserve, red_ship_reserve, brigades,
		auto_seed_followon_pool, escort_interception, escort_reload_turns > 0)


static func build_unopposed_offload_state(ship_reserve: Array) -> SealiftState:
	return SealiftStateBuilder.build_unopposed_offload_state(ship_reserve)


static func build_supply_state(red_dos_start: float) -> SupplyState:
	return SupplyStateBuilder.build(red_dos_start)


static func build_infrastructure_state(infrastructure: Dictionary) -> InfrastructureState:
	return InfrastructureStateBuilder.build(infrastructure)


## brigades: the full GameData.brigades map; filtered here to Green, non-destroyed (IJFS targets
## only living Green units), minus the brigades still in mobilization — those become targets when
## TurnConductor releases them onto the map (plan 0029 Tier A2).
##
## The exclusion is by mobilization membership, deliberately NOT by "has no hex". Every scenario is
## loaded against the full ROC OOB, so a scenario that places only some brigades (scenario_golden
## places 4 of 32) has always had its unplaced brigades in the target pool; narrowing that is a
## separate, golden-touching decision (docs/plans/BACKLOG.md), not this plan's.
## holdback: GameData.mobilization_holdback ([{brigade_id, garrison_hex}]), empty by default.
static func build_ijfs_state(
	antiship_containers: Array, brigades: Dictionary, holdback: Array = []
) -> IjfsDailyState:
	var mobilizing: Dictionary = {}
	for entry_value in holdback:
		mobilizing[String((entry_value as Dictionary)["brigade_id"])] = true
	var green_brigades: Array = []
	for brigade_value in brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.GREEN and not brigade.destroyed and not mobilizing.has(brigade.id):
			green_brigades.append(brigade)
	return IjfsStateBuilder.build(antiship_containers, green_brigades)


## Green brigades held in mobilization plus their release schedule (plan 0029 Tier A2).
## green_mobilization / holdback both come from GameData's scenario load.
static func build_mobilization_state(green_mobilization: Dictionary, holdback: Array) -> MobilizationState:
	return MobilizationStateBuilder.build(green_mobilization, holdback)


## Red battalions waiting to fly plus the per-turn lift budgets (plan 0032). red_air_insertion comes
## from GameData's scenario load; absent block => empty pool => the phase is inert.
static func build_air_insertion_state(red_air_insertion: Dictionary, brigades: Dictionary) -> AirInsertionState:
	return AirInsertionStateBuilder.build(red_air_insertion, brigades)
