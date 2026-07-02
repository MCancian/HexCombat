# Aggregate a batch's per-game records into a Markdown outcome report (harness B3).
#
# C:\Godot_v4.7-stable_win64.exe --headless --path C:\Users\mdogg\Desktop\HexCombat ^
#   -s res://tools/make_batch_report.gd -- --batch=<name-or-dir> [--out=<path>]
#
# --batch: a batch name under reports/batches/, or a full directory path containing
# games/*.json + manifest.json. Default --out is <batch-dir>/report.md.
extends SceneTree


func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1]
	if not args.has("batch"):
		push_error("Missing required --batch=<name-or-dir>")
		quit(1)
		return

	var batch := String(args["batch"])
	var batch_dir := batch if (batch.contains("/") or batch.contains("\\")) else "res://reports/batches/%s" % batch
	var games_dir := batch_dir.path_join("games")
	var dir := DirAccess.open(games_dir)
	if dir == null:
		push_error("No games directory at %s" % games_dir)
		quit(1)
		return

	var records: Array = []
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if not file_name.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(games_dir.path_join(file_name)))
		if parsed is Dictionary:
			records.append(parsed)
		else:
			push_error("Unparseable game record skipped: %s" % file_name)
	if records.is_empty():
		push_error("No game records in %s" % games_dir)
		quit(1)
		return

	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(batch_dir.path_join("manifest.json")))
	if not (manifest is Dictionary):
		manifest = {}

	var report := BatchReport.render_markdown(BatchReport.aggregate(records), manifest)
	var out_path := String(args.get("out", batch_dir.path_join("report.md")))
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write report to %s" % out_path)
		quit(1)
		return
	file.store_string(report)
	file.close()
	print("REPORT OK: %d record(s) -> %s" % [records.size(), out_path])
	quit(0)
