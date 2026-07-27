class_name ScenarioCatalog
extends RefCounted

## Scenario selection + enumeration (research-harness B1). Pure statics — no autoload access.
## DEFAULT_SCENARIO_PATH (scenario_default.json) is the RESEARCH default — the realistic sustained-
## sealift laydown a naked run / self-play gets. The pinned GATE does NOT run it: run_all_tests.sh/.ps1
## export HEXCOMBAT_SCENARIO=scenario_golden.json (the frozen assault fixture) so every validator/test
## stays byte-stable while scenario_default evolves. Variants are additive files under SCENARIOS_DIR,
## addressed by id (filename stem). A headless process selects a scenario with the `--scenario=<id-or-
## path>` user arg (after Godot's `--` separator) or the HEXCOMBAT_SCENARIO env var — the arg wins.
## No selection → the research default.

const DEFAULT_SCENARIO_PATH := "res://data/scenarios/scenario_default.json"
const SCENARIOS_DIR := "res://data/scenarios"
const SCENARIO_ARG_PREFIX := "--scenario="
const SCENARIO_ENV_VAR := "HEXCOMBAT_SCENARIO"


## The scenario path this process should load (reads OS args/env once at boot via
## GameData.load_all). Missing selected files are push_error'd here for an actionable message;
## the load itself then fails loud too — a typo'd selection must never silently run the default.
static func selected_path() -> String:
	return select_path(OS.get_cmdline_user_args(), OS.get_environment(SCENARIO_ENV_VAR))


## Pure core of selected_path (testable without OS state).
static func select_path(user_args: PackedStringArray, env_value: String) -> String:
	var selection := ""
	for arg in user_args:
		if arg.begins_with(SCENARIO_ARG_PREFIX):
			selection = arg.trim_prefix(SCENARIO_ARG_PREFIX)
			break
	if selection.is_empty():
		selection = env_value
	if selection.strip_edges().is_empty():
		return DEFAULT_SCENARIO_PATH
	var path := resolve_path(selection)
	if not FileAccess.file_exists(path):
		push_error("Selected scenario not found: '%s' (resolved to %s)" % [selection, path])
	return path


## Resolve an id or path: "" / "default" → the default scenario; anything with a path separator
## or a .json suffix is used as a path verbatim (res://, user://, or absolute OS paths all work);
## a bare id becomes SCENARIOS_DIR/<id>.json.
static func resolve_path(id_or_path: String) -> String:
	var trimmed := id_or_path.strip_edges()
	if trimmed.is_empty() or trimmed == "default":
		return DEFAULT_SCENARIO_PATH
	if trimmed.ends_with(".json") or trimmed.contains("/") or trimmed.contains("\\"):
		return trimmed
	return "%s/%s.json" % [SCENARIOS_DIR, trimmed]


## Reporting identity for a scenario path (filename stem; the default's is "scenario_default").
static func scenario_id(path: String) -> String:
	return path.get_file().get_basename()


## Every known scenario: the default first, then data/scenarios/*.json sorted by filename —
## the enumeration surface for the validator and (later) the batch runner.
static func list_scenario_paths() -> Array[String]:
	var dir := DirAccess.open(SCENARIOS_DIR)
	if dir == null:
		return [DEFAULT_SCENARIO_PATH]
	var names: Array[String] = []
	for file_name in dir.get_files():
		if file_name.ends_with(".json") and file_name != "scenario_golden.json":
			names.append(file_name)
	names.sort()
	
	var paths: Array[String] = [DEFAULT_SCENARIO_PATH]
	if names.has("scenario_default.json"):
		names.erase("scenario_default.json")
		
	for file_name in names:
		paths.append("%s/%s" % [SCENARIOS_DIR, file_name])
	return paths
