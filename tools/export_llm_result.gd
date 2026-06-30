# Export an LLM action result JSON fixture.
# Example:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/export_llm_result.gd -- --output=docs/examples/llm_result_after_turn.json
extends SceneTree

const DEFAULT_OUTPUT := "reports/llm_result.json"


func _initialize() -> void:
	var output_path := _parse_arg("--output=", DEFAULT_OUTPUT)
	var result := LLMFixtures.build_result()
	var absolute_output := _absolute_output_path(output_path)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	if dir_error != OK:
		push_error("Could not create output directory %s: %s" % [absolute_output.get_base_dir(), error_string(dir_error)])
		quit(1)
		return

	var file := FileAccess.open(absolute_output, FileAccess.WRITE)
	if file == null:
		push_error("Could not open result output for write: %s" % absolute_output)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("Wrote LLM result: %s" % absolute_output)
	quit(0)


func _parse_arg(prefix: String, default_value: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix).strip_edges().trim_prefix('"').trim_suffix('"')
	return default_value


func _absolute_output_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://%s" % path)
