# Capture the main scene to a PNG for LLM/human playtesting review.
# Example:
# C:\Godot_v4.7-stable_win64.exe --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/capture_screenshot.gd -- --output=reports/llm_screenshots/current.png
extends SceneTree

const DEFAULT_OUTPUT := "reports/llm_screenshots/current.png"


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Screenshot capture needs a rendering display; run without --headless")
		quit(1)
		return

	var output_path := _parse_output_path()
	var error := change_scene_to_file("res://scenes/Main.tscn")
	if error != OK:
		push_error("Could not load Main.tscn: %s" % error_string(error))
		quit(1)
		return

	await process_frame
	await process_frame
	await process_frame

	var absolute_output := _absolute_output_path(output_path)
	var output_dir := absolute_output.get_base_dir()
	var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if dir_error != OK:
		push_error("Could not create screenshot directory %s: %s" % [output_dir, error_string(dir_error)])
		quit(1)
		return

	var viewport_texture := root.get_viewport().get_texture()
	if viewport_texture == null:
		push_error("Viewport texture is unavailable; run without --headless for screenshot capture")
		quit(1)
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		push_error("Viewport image is empty; run without --headless if the renderer is unavailable")
		quit(1)
		return

	var save_error := image.save_png(absolute_output)
	if save_error != OK:
		push_error("Could not save screenshot %s: %s" % [absolute_output, error_string(save_error)])
		quit(1)
		return

	print("Saved screenshot: %s" % absolute_output)
	quit(0)


func _parse_output_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			return arg.trim_prefix("--output=").strip_edges().trim_prefix('"').trim_suffix('"')
	return DEFAULT_OUTPUT


func _absolute_output_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://%s" % path)
