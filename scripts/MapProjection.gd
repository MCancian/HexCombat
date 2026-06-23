extends RefCounted
class_name MapProjection

const LAT_MIN = 21.9
const LAT_MAX = 25.3
const LON_MIN = 119.9
const LON_MAX = 122.1

var viewport_size: Vector2 = Vector2(1920, 1080)


func _init(size: Vector2 = Vector2(1920, 1080)) -> void:
	viewport_size = size


func project(lat_lon: Vector2) -> Vector2:
	var lat := lat_lon.x
	var lon := lat_lon.y
	var x := (lon - LON_MIN) / (LON_MAX - LON_MIN) * viewport_size.x
	var y := (1.0 - (lat - LAT_MIN) / (LAT_MAX - LAT_MIN)) * viewport_size.y
	return Vector2(x, y)


func project_vertices(lat_lon_vertices: PackedVector2Array) -> PackedVector2Array:
	var projected := PackedVector2Array()
	for vertex in lat_lon_vertices:
		projected.append(project(vertex))
	return projected
