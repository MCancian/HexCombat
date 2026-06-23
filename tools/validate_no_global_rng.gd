# Run from the project root:
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat -s res://tools/validate_no_global_rng.gd
#
# Guards the M0 invariant: pure logic must not call Godot's GLOBAL RNG
# (randi/randf/randi_range/randf_range/randomize). Randomness must flow through an
# injected Dice so combat/sim outcomes stay reproducible and golden-testable.
# Method calls on an instance (e.g. SeededDice's `_rng.randi_range(...)`) are allowed.
extends SceneTree

const SCAN_ROOT := "res://scripts"
# Global RNG calls not preceded by a '.' (so `_rng.randi_range(` on an instance is fine).
const FORBIDDEN := "(^|[^.\\w])(randi|randf|randi_range|randf_range|randomize)\\s*\\("

var _failures: Array[String] = []


func _initialize() -> void:
	print("=== No-global-RNG validation (pure logic) ===")
	var regex := RegEx.new()
	var err := regex.compile(FORBIDDEN)
	if err != OK:
		_fail("Could not compile forbidden-RNG regex")
		_finish()
		return

	var scripts := _gd_files(SCAN_ROOT)
	print("Scanning %d .gd file(s) under %s" % [scripts.size(), SCAN_ROOT])
	for path in scripts:
		_scan_file(path, regex)
	_finish()


func _gd_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		_fail("Cannot open dir: %s" % root)
		return found
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full := "%s/%s" % [root, name]
		if dir.current_is_dir():
			found.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			found.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return found


func _scan_file(path: String, regex: RegEx) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Cannot read: %s" % path)
		return
	var line_no := 0
	while not file.eof_reached():
		var line := file.get_line()
		line_no += 1
		# Ignore comments.
		var code := line
		var hash_at := code.find("#")
		if hash_at != -1:
			code = code.substr(0, hash_at)
		if regex.search(code) != null:
			_fail("%s:%d global RNG call: %s" % [path, line_no, line.strip_edges()])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: no global RNG in pure logic")
		quit(0)
		return
	print("FAIL: no-global-RNG validation found %d issue(s):" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
	quit(1)
