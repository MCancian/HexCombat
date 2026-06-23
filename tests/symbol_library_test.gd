extends GdUnitTestSuite

const OOB_NATO_TYPES := [
	"air-defense",
	"amphibious",
	"area-command",
	"armor",
	"artillery",
	"aviation",
	"infantry",
	"mech-infantry",
	"motorized-infantry",
	"reserve",
	"special-forces",
]


func test_all_oob_nato_types_resolve_to_textures() -> void:
	var symbol_library := SymbolLibrary.new()
	for nato_type in OOB_NATO_TYPES:
		var texture := symbol_library.texture_for_nato_type(nato_type)
		assert_object(texture).is_not_null()
		assert_bool(texture is Texture2D).is_true()


func test_unmapped_nato_type_returns_null() -> void:
	var symbol_library := SymbolLibrary.new()
	await assert_error(func() -> void:
		var texture := symbol_library.texture_for_nato_type("not-a-real-type")
		assert_object(texture).is_null()
	).is_push_error("No NATO symbol mapped for nato_type 'not-a-real-type'")
