extends RefCounted
class_name LLMFixtures

## Single source of truth for the committed docs/examples/*.json LLM fixtures.
## BOTH the export tools (tools/export_llm_*.gd) and the drift gate (tools/validate_fixtures.gd)
## build through here, so a committed fixture and its regenerator can never silently diverge
## (refactor_audit item 8 — the rot that left llm_result_after_turn.json stale through the
## 2026-06-29/30 balance work). Each builder resets to a fresh scenario first, so calls are
## order-independent.

const RESULT_SEED := 20260624

## The canonical action sequence the result fixture records: Red lands (offload), moves one
## brigade into contact, then ends the turn under the fixed golden seed.
static func result_response() -> Dictionary:
	return {
		"protocol_version": LLMGameAPI.PROTOCOL_VERSION,
		"schema": LLMGameAPI.ACTION_RESPONSE_SCHEMA,
		"perspective_team": "Red",
		"actions": [
			{"type": "move", "team": "Red", "brigade_id": "PLA-71-2-Amphibious", "target_hex": "hex_43_16", "mode": Movement.MODE_TACTICAL},
			{"type": "end_turn", "seed": RESULT_SEED},
		],
	}


## Fresh turn-1 observation from the given perspective team ("" for neutral).
static func build_observation(team: String) -> Dictionary:
	_reset()
	return LLMGameAPI.observation(team)


## Action result after one fully-resolved turn (offload provisioned, then result_response applied).
static func build_result() -> Dictionary:
	_reset()
	_game_state().resolve_offload_turn(SeededDice.new(RESULT_SEED))
	return LLMGameAPI.apply_agent_response(result_response())


static func _reset() -> void:
	_game_data().load_all()
	_game_state().reset_to_scenario()


static func _game_data() -> Node:
	return Engine.get_main_loop().root.get_node("GameData")


static func _game_state() -> Node:
	return Engine.get_main_loop().root.get_node("GameState")
