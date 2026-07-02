# Render one game record into a readable turn-by-turn Markdown narrative (harness B4).
#
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat ^
#   -s res://tools/make_game_narrative.gd -- --record=<record.json> [--out=<path>]
#   -s res://tools/make_game_narrative.gd -- --batch=<name-or-dir> [--pick=median|longest|shortest] [--out=<path>]
#
# --batch picks a representative game across the batch's records by turns_played
# (median default; longest/shortest for the extremes). Default --out is <record>.narrative.md.
extends SceneTree


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1]

	var record_path := String(args.get("record", ""))
	if record_path.is_empty() and args.has("batch"):
		record_path = _pick_from_batch(String(args["batch"]), String(args.get("pick", "median")))
	if record_path.is_empty():
		push_error("Need --record=<record.json> or --batch=<name-or-dir> [--pick=median|longest|shortest]")
		quit(1)
		return

	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(record_path))
	if not (record is Dictionary):
		push_error("Could not parse game record: %s" % record_path)
		quit(1)
		return

	var out_path := String(args.get("out", "%s.narrative.md" % record_path.trim_suffix(".json")))
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write narrative to %s" % out_path)
		quit(1)
		return
	file.store_string(GameNarrative.render(record))
	file.close()
	print("NARRATIVE OK: %s -> %s" % [record_path, out_path])
	quit(0)


func _pick_from_batch(batch: String, pick: String) -> String:
	var batch_dir := batch if (batch.contains("/") or batch.contains("\\")) else "res://reports/batches/%s" % batch
	var games_dir := batch_dir.path_join("games")
	var dir := DirAccess.open(games_dir)
	if dir == null:
		push_error("No games directory at %s" % games_dir)
		return ""
	var entries: Array = []  # [{path, turns}]
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if not file_name.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(games_dir.path_join(file_name)))
		if parsed is Dictionary:
			entries.append({"path": games_dir.path_join(file_name), "turns": int((parsed as Dictionary).get("turns_played", 0))})
	if entries.is_empty():
		push_error("No parseable game records in %s" % games_dir)
		return ""
	entries.sort_custom(func(a, b): return a["turns"] < b["turns"] or (a["turns"] == b["turns"] and String(a["path"]) < String(b["path"])))
	match pick:
		"shortest":
			return String(entries[0]["path"])
		"longest":
			return String(entries[entries.size() - 1]["path"])
		_:
			return String(entries[entries.size() / 2]["path"])
