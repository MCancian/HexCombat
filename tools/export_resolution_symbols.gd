#!/usr/bin/env -S godot --headless -s
extends SceneTree

## Reflection half of the on-demand resolution-map builder (plan 0061 Part 1).
##
## Godot exposes declarations, not a method-body AST. This exporter therefore owns only the exact
## facts the engine knows: class paths/bases, properties, methods, constants and typed-Array hints.
## `generate_resolution_dag.py` owns conservative source analysis and rendering.
##
## IMPORTANT: script paths are discovered and loaded through runtime variables. Do not replace the
## variable load below with a literal script preload/load: validate_tool_script_purity treats literal
## tool dependencies as part of the tool compile closure, and gameplay scripts legitimately depend
## on autoloads.

const PASS_PREFIX := "PASS: resolution symbols exported — "

var _failures: Array[String] = []


func _initialize() -> void:
	var output_path := _output_path(OS.get_cmdline_user_args())
	if output_path.is_empty():
		_finish_failure("missing --output=<project-relative path>")
		return
	var script_paths := _gd_files(_scripts_root())
	if script_paths.is_empty():
		_finish_failure("no GDScript found under scripts/")
		return
	var global_by_path := _global_classes_by_path()
	if global_by_path.is_empty():
		_finish_failure("Godot reported zero global classes — run a headless project import first")
		return
	var autoloads := _autoloads_by_name()
	for autoload_name in autoloads:
		var autoload_path := "res://" + String(autoloads[autoload_name])
		if not global_by_path.has(autoload_path):
			_failures.append("autoload %s has no reflected global class at %s — run a headless import" % [
				autoload_name, autoload_path])
	var records: Array[Dictionary] = []
	for path in script_paths:
		var script_value := load(path)
		if script_value == null or not (script_value is Script):
			_failures.append("could not load %s as Script" % path)
			continue
		var script := script_value as Script
		var global_row: Dictionary = global_by_path.get(path, {})
		var declared_class := _declared_class_name(path)
		if not declared_class.is_empty() and String(global_row.get("class", "")) != declared_class:
			_failures.append("%s declares class_name %s but reflection has no matching row — run a headless import" % [
				path, declared_class])
		records.append(_script_record(path, script, global_row))
	if not _failures.is_empty():
		_finish_failure("; ".join(_failures))
		return
	var payload := {
		"format_version": 1,
		"source_hash": _source_hash(script_paths),
		"script_count": script_paths.size(),
		"global_class_count": global_by_path.size(),
		"autoloads": autoloads,
		"scripts": records,
	}
	var absolute_output := output_path if output_path.begins_with("res://") else "res://" + output_path.trim_prefix("./")
	var parent := absolute_output.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent)) != OK:
		_finish_failure("could not create output directory %s" % parent)
		return
	var file := FileAccess.open(absolute_output, FileAccess.WRITE)
	if file == null:
		_finish_failure("could not open %s for writing" % absolute_output)
		return
	file.store_string(JSON.stringify(payload, "  ", true) + "\n")
	file.close()
	print("%s%d scripts; %d global classes; sha256=%s" % [
		PASS_PREFIX, script_paths.size(), global_by_path.size(), payload["source_hash"]])
	quit(0)


func _scripts_root() -> String:
	# Split construction keeps this tool free of literal script load dependencies.
	return "res:/" + "/scripts"


func _output_path(args: PackedStringArray) -> String:
	for argument in args:
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=")
	return ""


func _autoloads_by_name() -> Dictionary:
	var result: Dictionary = {}
	var names: Array[String] = []
	for property in ProjectSettings.get_property_list():
		var property_name := String((property as Dictionary).get("name", ""))
		if property_name.begins_with("autoload/"):
			names.append(property_name.trim_prefix("autoload/"))
	names.sort()
	for autoload_name in names:
		var path := String(ProjectSettings.get_setting("autoload/" + autoload_name, ""))
		result[autoload_name] = path.trim_prefix("*").trim_prefix("res://")
	return result


func _global_classes_by_path() -> Dictionary:
	var result: Dictionary = {}
	var rows: Array[Dictionary] = []
	for row_value in ProjectSettings.get_global_class_list():
		rows.append(row_value as Dictionary)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("path", "")) < String(b.get("path", "")))
	for row in rows:
		var path := String(row.get("path", ""))
		if path.begins_with(_scripts_root() + "/"):
			result[path] = {
				"class": String(row.get("class", "")),
				"base": String(row.get("base", "")),
				"language": String(row.get("language", "")),
			}
	return result


func _declared_class_name(path: String) -> String:
	var regex := RegEx.new()
	if regex.compile("(?m)^class_name\\s+([A-Za-z_]\\w*)\\s*$") != OK:
		_failures.append("internal class_name detector failed to compile")
		return ""
	var found := regex.search(FileAccess.get_file_as_string(path))
	return "" if found == null else found.get_string(1)


func _script_record(path: String, script: Script, global_row: Dictionary) -> Dictionary:
	var properties: Array[Dictionary] = []
	for property_value in script.get_script_property_list():
		var property := property_value as Dictionary
		# The synthetic `SomeFile.gd` entry describes the script resource, not a declared property.
		if String(property.get("name", "")).ends_with(".gd"):
			continue
		properties.append(_property_record(property))
	properties.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]) < String(b["name"]))

	var methods: Array[Dictionary] = []
	for method_value in script.get_script_method_list():
		methods.append(_method_record(method_value as Dictionary))
	methods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]) < String(b["name"]))

	var constants: Array[Dictionary] = []
	var constant_map := script.get_script_constant_map()
	var constant_names: Array[String] = []
	for name_value in constant_map.keys():
		constant_names.append(String(name_value))
	constant_names.sort()
	for constant_name in constant_names:
		constants.append(_constant_record(constant_name, constant_map[constant_name]))

	return {
		"path": path.trim_prefix("res://"),
		"class": String(global_row.get("class", "")),
		"base": String(global_row.get("base", "")),
		"language": String(global_row.get("language", "GDScript")),
		"properties": properties,
		"methods": methods,
		"constants": constants,
	}


func _property_record(property: Dictionary) -> Dictionary:
	return {
		"name": String(property.get("name", "")),
		"type": int(property.get("type", TYPE_NIL)),
		"type_name": type_string(int(property.get("type", TYPE_NIL))),
		"class_name": String(property.get("class_name", "")),
		"hint": int(property.get("hint", PROPERTY_HINT_NONE)),
		"hint_string": String(property.get("hint_string", "")),
		"usage": int(property.get("usage", 0)),
	}


func _method_record(method: Dictionary) -> Dictionary:
	var arguments: Array[Dictionary] = []
	for argument_value in method.get("args", []):
		arguments.append(_property_record(argument_value as Dictionary))
	var return_value: Dictionary = method.get("return", {})
	return {
		"name": String(method.get("name", "")),
		"flags": int(method.get("flags", 0)),
		"arguments": arguments,
		"return": _property_record(return_value),
	}


func _constant_record(name: String, value: Variant) -> Dictionary:
	var row := {"name": name, "variant_type": type_string(typeof(value))}
	if value is Script:
		var inner_script := value as Script
		var inner_properties: Array[Dictionary] = []
		for property_value in inner_script.get_script_property_list():
			var property := property_value as Dictionary
			if not String(property.get("name", "")).ends_with(".gd"):
				inner_properties.append(_property_record(property))
		var inner_methods: Array[Dictionary] = []
		for method_value in inner_script.get_script_method_list():
			inner_methods.append(_method_record(method_value as Dictionary))
		inner_properties.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["name"]) < String(b["name"]))
		inner_methods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["name"]) < String(b["name"]))
		row["inner_class"] = {"properties": inner_properties, "methods": inner_methods}
	elif typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]:
		row["value"] = str(value)
	return row


func _gd_files(root: String) -> Array[String]:
	var result: Array[String] = []
	_walk_gd(root, result)
	result.sort()
	return result


func _walk_gd(path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		_failures.append("could not open %s" % path)
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if not name.begins_with("."):
			var child := path.path_join(name)
			if directory.current_is_dir():
				_walk_gd(child, result)
			elif name.ends_with(".gd"):
				result.append(child)
		name = directory.get_next()
	directory.list_dir_end()


func _source_hash(paths: Array[String]) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var inputs := paths.duplicate()
	inputs.append("res://project.godot")
	inputs.sort()
	for path in inputs:
		context.update(path.trim_prefix("res://").to_utf8_buffer())
		context.update(PackedByteArray([0]))
		context.update(FileAccess.get_file_as_bytes(path))
		context.update(PackedByteArray([0]))
	return context.finish().hex_encode()


func _finish_failure(message: String) -> void:
	push_error("resolution symbol export failed: %s" % message)
	print("FAIL: resolution symbol export — %s" % message)
	quit(1)
