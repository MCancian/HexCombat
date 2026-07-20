class_name GameStateBuilder
extends RefCounted

## Static scenario-load builders for GameState's typed sub-state (plan 0014 P2). Each method takes
## explicit GameData-sourced values (never the GameData or GameState autoload itself) and returns
## the built typed object; GameState.gd's `_rebuild_*` wrappers assign the result onto `data`. This
## is the seam that keeps GameState.gd's dependency count down: the per-type builders
## (ShipReserveBuilder, SealiftStateBuilder, FleetBuilder, SupplyStateBuilder,
## InfrastructureStateBuilder, AntishipSystemsBuilder, IjfsStateBuilder) are consumed here instead.


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


static func build_fleet(ship_defs: Dictionary) -> Dictionary:
	return FleetBuilder.build(ship_defs)


static func build_supply_state(red_dos_start: float) -> SupplyState:
	return SupplyStateBuilder.build(red_dos_start)


static func build_infrastructure_state(infrastructure: Dictionary) -> InfrastructureState:
	return InfrastructureStateBuilder.build(infrastructure)


## Returns {"systems": Array, "containers": Array} — the persistent Green anti-ship arsenal, keyed
## the same way AntishipSystemsBuilder.build() already returns it.
static func build_antiship_systems() -> Dictionary:
	return AntishipSystemsBuilder.build()


## brigades: the full GameData.brigades map; filtered here to Green, non-destroyed (IJFS targets
## only living Green units).
static func build_ijfs_state(antiship_containers: Array, brigades: Dictionary) -> IjfsDailyState:
	var green_brigades: Array = []
	for brigade_value in brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.team == Brigade.Team.GREEN and not brigade.destroyed:
			green_brigades.append(brigade)
	return IjfsStateBuilder.build(antiship_containers, green_brigades)
