extends RefCounted
class_name MapProjection

const LAT_MIN = 21.9
const LAT_MAX = 25.3
const LON_MIN = 119.9
const LON_MAX = 122.1

# Fraction of the viewport kept as empty margin on each side when fitting the map.
const MARGIN = 0.06

var viewport_size: Vector2 = Vector2(1920, 1080)

# Uniform, aspect-correct fit (computed once in _init).
var _lon_scale: float = 1.0  # cos(mean_lat): longitude degrees are shorter than latitude degrees
var _scale: float = 1.0      # pixels per latitude-degree
var _origin: Vector2 = Vector2.ZERO


func _init(size: Vector2 = Vector2(1920, 1080)) -> void:
	viewport_size = size

	var mean_lat := (LAT_MIN + LAT_MAX) / 2.0
	_lon_scale = cos(deg_to_rad(mean_lat))

	var content_w := (LON_MAX - LON_MIN) * _lon_scale
	var content_h := (LAT_MAX - LAT_MIN)
	var avail := viewport_size * (1.0 - 2.0 * MARGIN)
	_scale = min(avail.x / content_w, avail.y / content_h)

	var drawn := Vector2(content_w, content_h) * _scale
	_origin = (viewport_size - drawn) * 0.5


# Pixels per latitude-degree under the current fit (canonical map scale).
func scale() -> float:
	return _scale


func project(lat_lon: Vector2) -> Vector2:
	var lat := lat_lon.x
	var lon := lat_lon.y
	var x := _origin.x + (lon - LON_MIN) * _lon_scale * _scale
	var y := _origin.y + (LAT_MAX - lat) * _scale
	return Vector2(x, y)


func project_vertices(lat_lon_vertices: PackedVector2Array) -> PackedVector2Array:
	var projected := PackedVector2Array()
	for vertex in lat_lon_vertices:
		projected.append(project(vertex))
	return projected
