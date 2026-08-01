#!/usr/bin/env -S godot --headless -s
# Validates that every script path bound inside a .tscn RESOLVES to a real file (plan 0057).
#
# WHY THIS EXISTS. A scene binds its script by PATH STRING:
#
#   [ext_resource type="Script" path="res://scripts/ui/HexMap.gd" id="2_8gx3h"]
#
# Move the file without editing that line and nothing goes red. It is not a compile error — GDScript
# resolves `class_name` independently of location, so the whole engine still builds. The scene simply
# loads with a null script at runtime.
#
# The smoke phase is NOT the check for this, which is the trap plan 0057 was written believing:
#   * Smoke boots ONLY `run/main_scene` (`scenes/Main.tscn`). `scenes/SymbolPreview.tscn` is reachable
#     from no scene, no autoload and no test — measured 2026-07-31 — so before this validator its
#     binding had ZERO coverage anywhere in the gate. A move would have silently killed it and the
#     first symptom would have been a human opening the scene weeks later.
#   * Even for `Main.tscn`, smoke asserts four CONTENT markers and the absence of `SCRIPT ERROR`.
#     Nothing asserts a node still HAS a script, so coverage there is a side effect of what those
#     scripts happen to print — it would survive a node losing a script that prints nothing.
#
# WHAT THIS OWNS: every `ext_resource type="Script" path="..."` in every .tscn under res://scenes,
# and the assertion that each path names an existing file. It is deliberately a TEXT scan and not a
# scene load: loading needs a display server, can fail for reasons unrelated to placement, and would
# make a path typo indistinguishable from a broken node. A text scan fails for exactly one reason.
#
# WHAT THIS DOES NOT OWN: whether the script at that path is the RIGHT one, whether the node tree is
# correct, and any binding that is not a `.tscn` ext_resource (autoloads in `project.godot` are
# `tools/validate_autoload_paths.gd`'s job if that is ever wanted — today the 3 autoloads never move).
#
# Names no `class_name`, staying clear of the tools/ compile closure plan 0040 hit.
#
# Prints PASS:/FAIL: for the gate's verdict.
extends SceneTree

const SCENES_DIR := "res://scenes"

var _failures: Array[String] = []


func _initialize() -> void:
	if not _self_test():
		print("FAIL: scene-script-binding self-test failed — the parser is broken, so a green run would prove nothing")
		quit(1)
		return

	var scenes := _tscn_files(SCENES_DIR)
	if scenes.is_empty():
		print("FAIL: no .tscn files found under %s — either the path is wrong or the scenes were moved without updating this validator" % SCENES_DIR)
		quit(1)
		return

	var checked := 0
	for scene_path in scenes:
		var text := _read(scene_path)
		if text == "":
			_failures.append("%s could not be read" % scene_path)
			continue
		for script_path in _script_paths(text):
			checked += 1
			if not script_path.ends_with(".gd"):
				# Existence alone is not enough: every moved script has a `.gd.uid` sidecar sitting
				# right beside it, so a binding mistyped as `…/HexMap.gd.uid` names a file that DOES
				# exist and cannot load as a Script. Checking the extension first turns that into a
				# failure instead of a pass. (Review finding, 2026-07-31.)
				_failures.append("%s binds a script at %s, which is not a .gd file — it cannot load as a GDScript, so the node would end up with a null script even though the path resolves." % [
					scene_path, script_path])
				continue
			if not FileAccess.file_exists(script_path):
				_failures.append("%s binds a script at %s, which does not exist — a file was moved without updating the scene. The engine will NOT fail to compile; the node just loads with a null script." % [
					scene_path, script_path])

	if _failures.is_empty():
		print("PASS: scene script bindings — %d scene(s), %d binding(s) all resolve" % [scenes.size(), checked])
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FAIL: scene script bindings found %d issue(s)" % _failures.size())
	quit(1)


## Every `res://`-rooted path bound as a Script ext_resource in one .tscn's text.
func _script_paths(text: String) -> Array[String]:
	var paths: Array[String] = []
	var regex := RegEx.new()
	# `type` and `path` may appear in either order across Godot versions, so match the line and then
	# pull the path out of it rather than assuming the attribute order.
	regex.compile("\\[ext_resource[^\\]]*\\]")
	var path_regex := RegEx.new()
	path_regex.compile("path\\s*=\\s*\"([^\"]+)\"")
	for m in regex.search_all(text):
		var line := m.get_string()
		if not line.contains('type="Script"'):
			continue
		var path_match := path_regex.search(line)
		if path_match == null:
			_failures.append('an ext_resource declares type="Script" with no path= attribute: %s' % line)
			continue
		paths.append(path_match.get_string(1))
	return paths


func _tscn_files(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir():
			if not name.begins_with("."):
				files.append_array(_tscn_files("%s/%s" % [dir_path, name]))
		elif name.ends_with(".tscn"):
			files.append("%s/%s" % [dir_path, name])
		name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## The parser proves itself before it is trusted. Each case asserts a confusion that would otherwise
## make a green run meaningless — in particular that a NON-script ext_resource is not checked (a
## texture path is not this validator's business) and that a real binding IS found.
##
## TWO DELIBERATE CHOICES IN THIS FIXTURE, both learned the hard way on 2026-07-31:
##
##   1. SINGLE-quoted GDScript literals, so the `.tscn` double quotes need no backslash escaping.
##      `validate_tool_script_purity.gd` blanks string literals with `"[^"\n]*"`, which is NOT
##      escape-aware: a `\"` inside a double-quoted literal ends the match early and leaves the rest
##      of the fixture exposed as bare source. That is not a hypothetical — the first version of this
##      file used escaped quotes, leaked `HexMap` as an identifier, pulled it into the tool compile
##      closure, and turned the whole gate red with `scripts/ui/HexMap.gd names 'GameData'`, an error
##      pointing nowhere near the actual edit. Single quotes make the fixture strippable.
##
##   2. Script names that DO NOT EXIST (`ExampleView.gd`, `ExamplePanel.gd`). Belt-and-braces for the
##      same trap: even if a future stripper mis-parses this fixture, the identifiers it leaks name no
##      real class, so nothing is dragged into any closure. A self-test fixture must never name a
##      production class it is not actually testing against.
func _self_test() -> bool:
	var cases := [
		# [scene text, expected paths, why]
		['[ext_resource type="Script" path="res://scripts/ui/ExampleView.gd" id="2_8gx3h"]',
			["res://scripts/ui/ExampleView.gd"], "a plain script binding"],
		['[ext_resource type="Texture2D" path="res://art/hex.png" id="1"]',
			[], "a non-Script ext_resource is ignored"],
		['[ext_resource path="res://scripts/ui/ExamplePanel.gd" type="Script" id="4"]',
			["res://scripts/ui/ExamplePanel.gd"], "attributes in the other order"],
		['[node name="Root" type="Node2D"]\nscript = ExtResource("2")',
			[], "a node's script= reference is not an ext_resource declaration"],
		['[ext_resource type="Script" path="res://a.gd" id="1"]\n[ext_resource type="Script" path="res://b.gd" id="2"]',
			["res://a.gd", "res://b.gd"], "two bindings in one file"],
	]
	for case_value in cases:
		var case: Array = case_value
		var expected: Array = case[1]
		var before := _failures.size()
		var got := _script_paths(String(case[0]))
		_failures.resize(before)
		if got.size() != expected.size():
			push_error("self-test: %s — expected %d path(s), got %s" % [String(case[2]), expected.size(), str(got)])
			return false
		for i in got.size():
			if got[i] != String(expected[i]):
				push_error("self-test: %s — expected %s, got %s" % [String(case[2]), str(expected), str(got)])
				return false
	return true
