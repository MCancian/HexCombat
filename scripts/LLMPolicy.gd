extends RefCounted
class_name LLMPolicy

## LLM-backed policy (B6). Implements the SelfPlayPolicy contract
## (build_actions(observation) -> Array) as a THIN marshaller: serialize the perspective
## observation to JSON, shell out to an out-of-process sidecar that calls the model, then hand the
## sidecar's validated action array back to the runner. All HTTP, prompt templating, retry,
## JSON-repair and replay logging live in the sidecar (tools/llm_sidecar.py) — the engine never
## learns about the provider. Deliberately no GDScript networking.
##
## NONDETERMINISTIC by nature (the model is). Use only via SelfPlayRunner.play_game_seats, whose
## end_turn seed keeps the RESOLVER deterministic even though the DECIDER is not; the sidecar logs
## every observation/action pair so the game is replayable regardless.
##
## Provider config is read from the ENVIRONMENT by the sidecar (inherited from this process):
## HEXCOMBAT_LLM_BASE_URL, HEXCOMBAT_LLM_MODEL, HEXCOMBAT_LLM_API_KEY. This policy passes only the
## per-call facts on argv: the observation file, the seat perspective, and the log path.

const DEFAULT_SIDECAR := "res://tools/llm_sidecar.py"

var perspective: String = ""            ## "Red" or "Green" — the seat this policy plays.
var sidecar_path: String = DEFAULT_SIDECAR
var log_path: String = ""               ## JSONL obs/action log; empty = sidecar's own default/none.

var _python_bin: String = ""            ## resolved lazily & cached on first build_actions.


static func for_seat(seat: String, jsonl_log_path: String = "") -> LLMPolicy:
	var p := LLMPolicy.new()
	p.perspective = seat
	p.log_path = jsonl_log_path
	return p


func build_actions(observation: Dictionary) -> Array:
	var interpreter := _resolve_python()
	if interpreter.is_empty():
		push_warning("LLMPolicy(%s): no python interpreter found — no actions this turn" % perspective)
		return []

	var obs_path := _write_temp_observation(observation)
	if obs_path.is_empty():
		return []

	var args: Array = [
		ProjectSettings.globalize_path(sidecar_path),
		"--obs=%s" % obs_path,
		"--perspective=%s" % perspective,
	]
	if not log_path.is_empty():
		args.append("--log=%s" % ProjectSettings.globalize_path(log_path))

	var out: Array = []
	# read_stderr = false: the sidecar prints ONLY the JSON action array to stdout; diagnostics go
	# to stderr (surfaced on the console) so they never corrupt the parse.
	var code := OS.execute(interpreter, args, out, false)
	DirAccess.remove_absolute(obs_path)

	if code != 0:
		push_warning("LLMPolicy(%s): sidecar exit %d — no actions this turn" % [perspective, code])
		return []

	var actions: Variant = _parse_actions("".join(out))
	if actions == null:
		push_warning("LLMPolicy(%s): unparseable sidecar output — no actions this turn" % perspective)
		return []
	return _strip_end_turn(actions)


## Parse the sidecar's stdout into an action Array. Accepts either a bare JSON array or an object
## with an "actions" array. Returns null on anything unparseable (caller treats as no-op).
func _parse_actions(text: String) -> Variant:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return []
	var parsed = JSON.parse_string(trimmed)
	if parsed is Array:
		return parsed
	if parsed is Dictionary and (parsed as Dictionary).get("actions", null) is Array:
		return (parsed as Dictionary)["actions"]
	return null


## Drop any end_turn action — the runner owns turn resolution and its seed. A seat policy must not
## be able to advance the turn on its own.
func _strip_end_turn(actions: Array) -> Array:
	var kept: Array = []
	for a in actions:
		if a is Dictionary and String((a as Dictionary).get("type", "")) == "end_turn":
			continue
		kept.append(a)
	return kept


func _write_temp_observation(observation: Dictionary) -> String:
	var path := OS.get_cache_dir().path_join("hexcombat_obs_%s_%d.json" % [
		perspective if not perspective.is_empty() else "any", Time.get_ticks_usec()
	])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("LLMPolicy(%s): could not write observation temp file %s" % [perspective, path])
		return ""
	file.store_string(JSON.stringify(observation))
	file.close()
	return path


## Resolve a working python interpreter once: HEXCOMBAT_LLM_PYTHON, else python3, else python.
func _resolve_python() -> String:
	if not _python_bin.is_empty():
		return _python_bin
	var candidates: Array[String] = []
	var from_env := OS.get_environment("HEXCOMBAT_LLM_PYTHON")
	if not from_env.is_empty():
		candidates.append(from_env)
	candidates.append_array(["python3", "python"])
	for candidate in candidates:
		var probe: Array = []
		if OS.execute(candidate, ["--version"], probe, false) == 0:
			_python_bin = candidate
			return _python_bin
	return ""
