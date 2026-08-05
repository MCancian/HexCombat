# Run from the project root:
# godot --headless --path . -s res://tools/validate_headless_infrastructure.gd
#
# Scripted end-to-end check of the plan-0006 infrastructure gate wiring: seizure via hex
# ownership through GameState.resolve_offload_turn, JLSF repair progression, and the
# red_offload_nodes rates. Scripted because empty-orders smoke runs never capture a port hex.
#
# Red ownership of a port hex is produced the way the GAME produces it (plan 0047 step 4): the
# golden Red mover is placed on the hex through the force authority and ownership is recomputed.
# The old shortcut, GameData.set_hex_owner, asserted an owner that nothing occupied — a generic
# setter whose only remaining caller was this file, and which the map authority deliberately does
# not offer. Moving the SAME brigade on to the second port additionally exercises two behaviours
# end to end that no unit test reaches through the real turn: sticky ownership of the emptied hex,
# and seizure persisting after Red moves inland.
extends SceneTree

const DICE_SEED := 12345
const RED_MOVER_ID := GoldenScript.RED_MOVER_ID
const PORT_ID := "taichung"
const PORT_HEX := "hex_33_7"
const JLSF_PORT_ID := "kaohsiung"
const JLSF_PORT_HEX := "hex_11_4"

var _h := ValidatorHarness.new("Headless infrastructure validation")
var GameData: Node = null
var GameState: Node = null


func _initialize() -> void:
	print("=== Headless infrastructure validation ===")
	GameData = get_root().get_node("GameData")
	GameState = get_root().get_node("GameState")
	if GameData == null or GameState == null:
		_h.fail("Autoloads GameData/GameState not found on the SceneTree root")
		_h.finish(self)
		return

	GameData.load_all()
	GameState.reset_to_scenario()
	_validate_initial_state()
	_validate_seizure_via_offload_turn()
	_validate_jlsf_repair_progression()
	_h.finish(self)


func _validate_initial_state() -> void:
	var state: InfrastructureState = GameState.infrastructure_state
	if state == null:
		_h.fail("GameState.infrastructure_state is null after reset_to_scenario")
		return
	_h.equal_int("infrastructure node count", state.nodes.size(), GameData.infrastructure.size())
	for id in state.nodes.keys():
		var node: InfrastructureNodeState = state.nodes[id]
		if node.node_status != InfrastructureState.STATUS_TAIWANESE:
			_h.fail("node %s starts %s, expected taiwanese" % [id, node.node_status])
	_assert_true("initial red_offload_nodes empty",
		InfrastructureResolver.red_offload_nodes(state, GameData.infrastructure, _owners()).is_empty())


func _validate_seizure_via_offload_turn() -> void:
	_occupy_with_red_mover(PORT_HEX)
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	var state: InfrastructureState = GameState.infrastructure_state
	var node: InfrastructureNodeState = state.nodes[PORT_ID]
	_h.equal_string("%s status after Red seizure turn" % PORT_ID, node.node_status, InfrastructureState.STATUS_SEIZED)
	# Seized contributes nothing.
	for entry in InfrastructureResolver.red_offload_nodes(state, GameData.infrastructure, _owners()):
		if String(entry["id"]) == PORT_ID:
			_h.fail("seized %s must not appear in red_offload_nodes" % PORT_ID)


## Move the Red mover on to the second port. The first port is thereby EMPTIED, which is the
## interesting half: sticky ownership must keep it Red and its node must stay seized.
func _validate_jlsf_repair_progression() -> void:
	_occupy_with_red_mover(JLSF_PORT_HEX)
	var state: InfrastructureState = GameState.infrastructure_state
	_h.equal_string("%s stays red after Red moves inland" % PORT_HEX,
		String(GameData.hex_states[PORT_HEX].hex_owner), HexOwner.RED)
	var first_port: InfrastructureNodeState = state.nodes[PORT_ID]
	_h.equal_string("%s stays seized after Red moves inland" % PORT_ID,
		first_port.node_status, InfrastructureState.STATUS_SEIZED)

	# Seize on the first offload tick, then simulate an arrived JLSF: +1 turn degraded, +2 operational.
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	var node: InfrastructureNodeState = state.nodes[JLSF_PORT_ID]
	_h.equal_string("%s seized" % JLSF_PORT_ID, node.node_status, InfrastructureState.STATUS_SEIZED)
	InfrastructureTransitions.mark_jlsf_arrived(state, JLSF_PORT_ID)
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	_h.equal_string("%s degraded after 1 repair turn" % JLSF_PORT_ID, node.node_status, InfrastructureState.STATUS_DEGRADED)
	# The degraded rate is asserted HERE, mid-progression, rather than by forcing a status on a node
	# the way the deleted _validate_rates_by_status did — same coverage, reached through the real
	# repair clock. The full (kind, status) rate matrix is unit-tested in
	# tests/infrastructure_resolver_test.gd::test_red_offload_rates.
	_assert_equal_float("degraded port rate", _rate_of(JLSF_PORT_ID), OffloadRates.DEGRADED_PORT)
	GameState.resolve_offload_turn(SeededDice.new(DICE_SEED))
	_h.equal_string("%s operational after 2 repair turns" % JLSF_PORT_ID, node.node_status, InfrastructureState.STATUS_OPERATIONAL)
	_assert_equal_float("repaired port rate", _rate_of(JLSF_PORT_ID), OffloadRates.OPERATIONAL_PORT)


## Put the golden Red mover on `hex_id` through the force authority and recompute ownership — the
## same two operations a real turn performs. Fails loudly rather than continuing if the hex does not
## come out Red, because every later assertion in this file silently depends on it.
func _occupy_with_red_mover(hex_id: String) -> void:
	if GameData.get_brigade(RED_MOVER_ID) == null:
		_h.fail("missing Red mover %s; cannot script hex ownership" % RED_MOVER_ID)
		return
	GameData.set_brigade_hex(RED_MOVER_ID, hex_id)
	GameData.recompute_hex_ownership()
	_h.equal_string("%s owner after placing %s" % [hex_id, RED_MOVER_ID],
		String(GameData.hex_states[hex_id].hex_owner), HexOwner.RED)


func _rate_of(infra_id: String) -> float:
	var state: InfrastructureState = GameState.infrastructure_state
	for entry in InfrastructureResolver.red_offload_nodes(state, GameData.infrastructure, _owners()):
		if String(entry["id"]) == infra_id:
			return float(entry["rate_tons"])
	return -1.0


func _owners() -> Dictionary:
	var owners: Dictionary = {}
	for hex_id in GameData.hex_states.keys():
		owners[String(hex_id)] = String(GameData.hex_states[hex_id].hex_owner)
	return owners


func _assert_equal_float(label: String, got: float, expected: float) -> void:
	if not is_equal_approx(got, expected):
		_h.fail("%s: expected %s, got %s" % [label, expected, got])


func _assert_true(label: String, condition: bool) -> void:
	if not condition:
		_h.fail(label)
