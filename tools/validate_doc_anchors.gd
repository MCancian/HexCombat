# Doc-anchor freshness gate (docs architecture B, 2026-07-10). Module docs rot when code moves
# under them — the audit that motivated this found three docs/systems/*.md citing functions that
# no longer existed and line numbers hundreds of lines stale. This validator makes that class of
# rot a RED GATE instead of a prose rule:
#
#   1. No `file.gd:123` line-number citations in docs/systems/*.md (line numbers rot silently;
#      the docs-and-writing rule is "class names only — the reader greps").
#   2. Every backticked repo path (`scripts/...`, `tools/...`, `data/...`, `tests/...`,
#      `schemas/...`) must exist on disk.
#   3. Every backticked bare `SomeFile.gd` basename must exist under scripts/, tools/, or tests/.
#   4. Every backticked `UpperCamel.member` reference (e.g. `IjfsResolver.compute_writeback`)
#      whose UpperCamel resolves to a .gd file must find `member` in that file's text.
#
# Escape hatch: lines mentioning `docs/archive` or containing the marker `(historical)` are
# skipped — historical passages may cite dead names on purpose. Semantic rot (a wrong claim in
# valid prose) stays a human/agent problem; this only catches dead anchors, which the audit
# showed is the dominant failure mode.
#
#   5. Every `docs/plans/<name>.md` or `docs/archive/<name>.md` token anywhere under docs/**/*.md
#      or tools/**/*.gd must resolve to a real file — NOT subject to the historical/archive
#      escape hatch above (that hatch is for stale script/member citations *within* a historical
#      passage; a doc-to-doc pointer should always resolve, historical or not, since plan
#      closeout moves a file rather than deleting the fact). Added 2026-07-11 after a plan
#      closeout move left four such references dead across docs/STATUS.md,
#      docs/antiship_missile_pipeline_ref.md, and two tools/*.gd comments, caught only by manual
#      grep.
extends SceneTree

const DOCS_DIR := "res://docs/systems"
const CODE_ROOTS := ["res://scripts", "res://tools", "res://tests"]
const DOC_LINK_SCAN_ROOTS := [
	["res://docs", ".md"],
	["res://tools", ".gd"],
]

var _failures: Array[String] = []
var _gd_index: Dictionary = {}  # basename -> full res:// path


func _initialize() -> void:
	_build_gd_index()
	var dir := DirAccess.open(DOCS_DIR)
	if dir == null:
		push_error("Cannot open %s" % DOCS_DIR)
		quit(1)
		return
	var checked := 0
	for file in dir.get_files():
		if not file.ends_with(".md"):
			continue
		_check_doc("%s/%s" % [DOCS_DIR, file])
		checked += 1

	var link_files_checked := _check_doc_links()

	if _failures.is_empty():
		print("PASS: doc anchors fresh (%d docs, %d indexed .gd files, %d files checked for dead doc-links)" % [checked, _gd_index.size(), link_files_checked])
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: doc-anchor validation found %d issue(s) — a code move/rename left dead anchors; update the doc (or mark the line '(historical)')" % _failures.size())
		quit(1)


func _check_doc(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var doc := path.get_file()
	var line_cite := RegEx.create_from_string("\\.gd:\\d+")
	var backtick := RegEx.create_from_string("`([^`\\n]+)`")
	var member_ref := RegEx.create_from_string("^([A-Z][A-Za-z0-9]+)\\.([a-zA-Z_][A-Za-z0-9_]*)")
	var lines := text.split("\n")
	for i in range(lines.size()):
		var line := lines[i]
		if line.contains("docs/archive") or line.contains("(historical)"):
			continue
		if line_cite.search(line) != null:
			_failures.append("%s:%d: file:line citation (line numbers rot — cite the class name): %s" % [doc, i + 1, line.strip_edges().left(90)])
		for m in backtick.search_all(line):
			var token := m.get_string(1).strip_edges()
			_check_token(doc, i + 1, token, member_ref)


func _check_token(doc: String, line_no: int, token: String, member_ref: RegEx) -> void:
	if token.contains("*"):
		return  # glob illustration, not an anchor
	# 2) explicit repo paths (strip :line suffixes, [key] indexing, trailing anchors)
	for root in ["scripts/", "tools/", "data/", "tests/", "schemas/"]:
		if token.begins_with(root):
			var clean := token.split(" ")[0].split("#")[0].split("[")[0].split(":")[0]
			if clean.ends_with("/"):
				clean = clean.trim_suffix("/")
			if not (FileAccess.file_exists("res://" + clean) or DirAccess.dir_exists_absolute("res://" + clean)):
				_failures.append("%s:%d: dead path `%s`" % [doc, line_no, token])
			return
	# 3) bare .gd basename (strip :line suffix — the file:line check reports the citation itself)
	if token.contains(".gd"):
		var base := token.split(":")[0]
		if not base.contains("/") and base.ends_with(".gd") and not _gd_index.has(base):
			_failures.append("%s:%d: no such script `%s` under scripts/tools/tests" % [doc, line_no, token])
		return
	# 4) UpperCamel.member — only when the class resolves to a known file
	var m := member_ref.search(token)
	if m == null:
		return
	var script_path: String = _gd_index.get(m.get_string(1) + ".gd", "")
	if script_path.is_empty():
		return
	var member := m.get_string(2)
	if member == "new":
		return  # Godot constructor, always valid
	if not FileAccess.get_file_as_string(script_path).contains(member):
		_failures.append("%s:%d: `%s` — no '%s' in %s (renamed/moved?)" % [doc, line_no, token, member, script_path.get_file()])


# Check 5 (see header): every docs/plans/<name>.md or docs/archive/<name>.md token under
# docs/**/*.md or tools/**/*.gd must resolve to a real file. Not gated by the historical/archive
# escape hatch used by _check_doc — a moved-but-not-deleted plan should always resolve.
func _check_doc_links() -> int:
	var link_re := RegEx.create_from_string("docs/(plans|archive)/[A-Za-z0-9_.\\-]+\\.md")
	var files: Array[String] = []
	for entry in DOC_LINK_SCAN_ROOTS:
		_collect_files(entry[0], entry[1], files)
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		var lines := text.split("\n")
		for i in range(lines.size()):
			for m in link_re.search_all(lines[i]):
				var token := m.get_string()
				if token.contains("*"):
					continue  # glob illustration, not an anchor
				if not FileAccess.file_exists("res://" + token):
					_failures.append("%s:%d: dead doc-link `%s`" % [path.trim_prefix("res://"), i + 1, token])
	return files.size()


func _collect_files(root: String, suffix: String, out: Array[String]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect_files("%s/%s" % [root, sub], suffix, out)
	for file in dir.get_files():
		if file.ends_with(suffix):
			out.append("%s/%s" % [root, file])


func _build_gd_index() -> void:
	for root in CODE_ROOTS:
		_index_dir(root)


func _index_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_index_dir("%s/%s" % [path, sub])
	for file in dir.get_files():
		if file.ends_with(".gd"):
			_gd_index[file] = "%s/%s" % [path, file]
