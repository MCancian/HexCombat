extends RefCounted
class_name SymbolLibrary

const SYMBOL_MAP_PATH := "res://data/nato_symbol_map.json"

var _symbol_dir: String = ""
var _nato_type_to_symbol: Dictionary = {}
var _texture_cache: Dictionary = {}


func _init() -> void:
	var map_doc := _read_json(SYMBOL_MAP_PATH)
	_symbol_dir = String(map_doc.get("symbol_dir", ""))
	_nato_type_to_symbol = map_doc.get("nato_type_to_symbol", {})
	if _symbol_dir.is_empty():
		push_error("symbol_dir missing or empty in %s" % SYMBOL_MAP_PATH)
	if not (_nato_type_to_symbol is Dictionary) or _nato_type_to_symbol.is_empty():
		push_error("nato_type_to_symbol missing or empty in %s" % SYMBOL_MAP_PATH)


func texture_for_nato_type(nato_type: String) -> Texture2D:
	if not _nato_type_to_symbol.has(nato_type):
		push_error("No NATO symbol mapped for nato_type '%s'" % nato_type)
		return null

	if _texture_cache.has(nato_type):
		return _texture_cache[nato_type]

	var path := "%s/%s" % [_symbol_dir, String(_nato_type_to_symbol[nato_type])]
	var resource := load(path)
	if resource == null or not (resource is Texture2D):
		push_error("NATO symbol for nato_type '%s' did not load as Texture2D: %s" % [nato_type, path])
		return null

	var texture := resource as Texture2D
	_texture_cache[nato_type] = texture
	return texture


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("%s did not parse to a Dictionary" % path)
		return {}
	return parsed
