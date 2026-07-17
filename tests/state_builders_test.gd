extends GdUnitTestSuite

## Behavioral tests for the pure GameState builders (plan 0009, phase B):
## SupplyStateBuilder, ShipReserveBuilder, FleetBuilder, AntishipSystemsBuilder.
## Deterministic — no dice. Fixtures built inline; AntishipSystemsBuilder reads the real
## data/antiship/*.json (its paths are its contract), asserted structurally, not by pin.


# --- fixture helpers ----------------------------------------------------------------------------

func _battalion(type: String, qty: int) -> Battalion:
	var battalion := Battalion.new()
	battalion.type = type
	battalion.qty = qty
	return battalion


func _brigade(id: String, composition: Array[Battalion]) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = id
	brigade.team = Brigade.Team.RED
	brigade.composition = composition
	return brigade


func _ship_def(name: String, total_count: int) -> ShipDef:
	var ship_def := ShipDef.new()
	ship_def.name = name
	ship_def.id = name.hash()
	ship_def.total_count = total_count
	return ship_def


func _reserve_entry(brigade_id: String) -> Dictionary:
	return {
		"brigade_id": brigade_id,
		"locked_beach": 1,
		"beach_hex": "hex_44_16",
		"offset_bearing": 90.0,
	}


# --- SupplyStateBuilder ---------------------------------------------------------------------------

func test_supply_state_pool_is_dos_times_tons_per_dos() -> void:
	var supply_state := SupplyStateBuilder.build(8.0)
	assert_float(supply_state.current_dos_tons).is_equal_approx(8.0 * DosConsumption.TONS_PER_DOS, 0.0001)
	assert_array(supply_state.day_history).is_empty()


func test_supply_state_zero_dos_gives_empty_pool() -> void:
	var supply_state := SupplyStateBuilder.build(0.0)
	assert_float(supply_state.current_dos_tons).is_equal_approx(0.0, 0.0001)


# --- ShipReserveBuilder ---------------------------------------------------------------------------

func test_ship_reserve_expands_battalion_instances_with_slug_ids() -> void:
	var composition: Array[Battalion] = [_battalion("Amphibious Armor Battalion", 2), _battalion("Artillery Battalion", 1)]
	var brigades := {"BdeA": _brigade("BdeA", composition)}
	var reserve := ShipReserveBuilder.build([_reserve_entry("BdeA")], brigades)

	assert_int(reserve.size()).is_equal(1)
	var entry: Dictionary = reserve[0]
	assert_str(String(entry["brigade_id"])).is_equal("BdeA")
	assert_int(int(entry["locked_beach"])).is_equal(1)
	assert_str(String(entry["beach_hex"])).is_equal("hex_44_16")
	assert_float(float(entry["offset_bearing"])).is_equal_approx(90.0, 0.0001)

	# qty 2 + qty 1 -> 3 BN records; ids use the lowercase-underscore slug + running index.
	var bns: Array = entry["bns"]
	assert_int(bns.size()).is_equal(3)
	assert_str(String((bns[0] as Dictionary)["id"])).is_equal("BdeA-amphibious_armor_battalion-1")
	assert_str(String((bns[1] as Dictionary)["id"])).is_equal("BdeA-amphibious_armor_battalion-2")
	assert_str(String((bns[2] as Dictionary)["id"])).is_equal("BdeA-artillery_battalion-3")
	assert_str(String((bns[2] as Dictionary)["type"])).is_equal("Artillery Battalion")


func test_ship_reserve_unknown_brigade_is_skipped() -> void:
	var reserve := ShipReserveBuilder.build([_reserve_entry("Ghost")], {})
	assert_array(reserve).is_empty()


# --- FleetBuilder ---------------------------------------------------------------------------------

func test_fleet_builder_creates_ready_untouched_ship_states() -> void:
	var ship_defs := {"LHA": _ship_def("LHA", 7), "DDG": _ship_def("DDG", 12)}
	var fleet := FleetBuilder.build(ship_defs)

	assert_int(fleet.size()).is_equal(2)
	var lha: ShipState = fleet["LHA"]
	assert_str(lha.ship_type).is_equal("LHA")
	assert_int(lha.fleet_total).is_equal(7)
	assert_int(lha.fleet_surviving_total).is_equal(7)
	assert_int(lha.ready).is_equal(7)
	assert_int(lha.sent_original).is_equal(0)
	assert_int(lha.surviving_sent).is_equal(0)
	assert_int(lha.offloading).is_equal(0)
	assert_int(lha.returning).is_equal(0)
	assert_int(lha.destroyed).is_equal(0)
	assert_int((fleet["DDG"] as ShipState).ready).is_equal(12)


# --- AntishipSystemsBuilder -----------------------------------------------------------------------

func test_antiship_builder_produces_consistent_systems_and_containers() -> void:
	var arsenal := AntishipSystemsBuilder.build()
	var systems: Array = arsenal["systems"]
	var containers: Array = arsenal["containers"]
	assert_bool(systems.is_empty()).is_false()
	assert_bool(containers.is_empty()).is_false()

	# Both views describe the same arsenal: per-(to, type) quantities must reconcile.
	var quantity_by_key: Dictionary = {}
	for system_value in systems:
		var system: AntishipSystem = system_value
		assert_int(system.quantity).is_greater_equal(0)
		assert_int(system.original_quantity).is_equal(system.quantity)
		var key := "%d:%d" % [system.to_number, system.type_id]
		quantity_by_key[key] = int(quantity_by_key.get(key, 0)) + system.quantity

	var container_quantity_by_key: Dictionary = {}
	for container_value in containers:
		var container: Dictionary = container_value
		var key := "%d:%d" % [int(container["to_number"]), int(container["type_id"])]
		container_quantity_by_key[key] = int(container_quantity_by_key.get(key, 0)) + int(container["systems_represented"])

	for key in quantity_by_key.keys():
		assert_int(int(container_quantity_by_key.get(key, -1))) \
			.override_failure_message("container total mismatch for %s" % key) \
			.is_equal(int(quantity_by_key[key]))
