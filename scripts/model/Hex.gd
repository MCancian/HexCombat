extends Resource
class_name Hex

@export var id: String = ""
@export var coord: Vector2i = Vector2i.ZERO
@export var row: int = 0
@export var col: int = 0
@export var center: Vector2 = Vector2.ZERO  # x = lat, y = lon
@export var vertices: PackedVector2Array = PackedVector2Array()  # x = lat, y = lon
