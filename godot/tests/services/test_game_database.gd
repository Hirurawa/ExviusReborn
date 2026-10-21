extends "res://tests/test_case.gd"

## Town maps are keyed by resource_map, not by their display icons. Event towns
## can reuse another town's icon, and Farplane has no map_icon_* filename at all.


func test_town_folder_comes_from_the_map_resource() -> void:
	assert_eq(GameDatabase.get_town("2100").get("mapFolderId"), "121010100", "Dirando Shore")
	assert_eq(GameDatabase.get_town("9001").get("mapFolderId"), "211020100", "Farplane")


func test_town_scene_prefers_the_map_resource_over_the_display_icon() -> void:
	var town_map: Node = preload("res://features/town/town_map.gd").new()
	# Dirando Shore reuses another town's icon, while Farplane has no usable map icon.
	assert_eq(town_map._resolve_town_folder_id("2100"), "121010100", "Dirando Shore")
	assert_eq(town_map._resolve_town_folder_id("9001"), "211020100", "Farplane")
	town_map.free()
