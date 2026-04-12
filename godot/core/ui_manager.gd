extends Node

var canvas_layer: CanvasLayer
var _menu_stack: Array[Node] = []

var top_header: Node = null
var bottom_nav: Node = null
var world_map_button: Node = null
var user_menu_button: Node = null

# Add standard menu mappings for easier instancing
var _scenes_map: Dictionary = {
	"login_ui": "res://features/auth/LoginUI.tscn",
	"register_ui": "res://features/auth/RegisterUI.tscn",
	"game_ui": "res://features/shared/GameUI.tscn",
	"edit_profile_ui": "res://features/outgame/profile/EditProfileUI.tscn",
	"shop_ui": "res://features/outgame/shop/ShopUI.tscn",
	"map_ui": "res://features/outgame/map/MapUI.tscn",
	"units_ui": "res://features/outgame/units/UnitsUI.tscn",
	"unit_selector_ui": "res://features/outgame/units/UnitSelectorUI.tscn",
	"unit_stats_popup": "res://features/outgame/units/UnitStatsPopup.tscn",
	"unit_detail_ui": "res://features/outgame/units/UnitDetailUI.tscn",
	"items_ui": "res://features/outgame/inventory/ItemsUI.tscn",
	"friends_ui": "res://features/outgame/friends/FriendsUI.tscn",
	"summon_ui": "res://features/outgame/summon/SummonUI.tscn",
	"equip_selection_popup": "res://features/outgame/equipment/EquipSelectionPopup.tscn",
	"combat_ui": "res://features/battle/ui/CombatUI.tscn"
}

func _ready() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "UIManagerCanvasLayer"
	add_child(canvas_layer)

	_load_persistent_overlays()

func _load_persistent_overlays() -> void:
	# These will be created in step 2. We'll instance them and set visibility.
	if ResourceLoader.exists("res://features/shared/TopHeader.tscn"):
		var top_scene: PackedScene = preload("res://features/shared/TopHeader.tscn")
		top_header = top_scene.instantiate()
		top_header.hide()
		canvas_layer.add_child(top_header)

	if ResourceLoader.exists("res://features/shared/BottomNav.tscn"):
		var bottom_scene: PackedScene = preload("res://features/shared/BottomNav.tscn")
		bottom_nav = bottom_scene.instantiate()
		bottom_nav.hide()
		canvas_layer.add_child(bottom_nav)

	if ResourceLoader.exists("res://features/shared/WorldMapButton.tscn"):
		var map_btn_scene: PackedScene = preload("res://features/shared/WorldMapButton.tscn")
		world_map_button = map_btn_scene.instantiate()
		world_map_button.hide()
		world_map_button.pressed.connect(_on_world_map_pressed)
		canvas_layer.add_child(world_map_button)

	if ResourceLoader.exists("res://features/shared/UserMenuButton.tscn"):
		var user_menu_scene: PackedScene = preload("res://features/shared/UserMenuButton.tscn")
		user_menu_button = user_menu_scene.instantiate()
		user_menu_button.hide()
		user_menu_button.get_popup().id_pressed.connect(_on_user_menu_pressed)
		canvas_layer.add_child(user_menu_button)

func _on_world_map_pressed() -> void:
	push("map_ui")

func _on_user_menu_pressed(id: int) -> void:
	if id == 0:
		push("edit_profile_ui")
	elif id == 1:
		DataManager.logout()
		set_root("login_ui")

func _update_overlays() -> void:
	if _menu_stack.is_empty():
		return

	var current_scene_name: String = _menu_stack.back().get_meta("scene_key", _menu_stack.back().name.to_lower())

	# Determine overlay visibility based on context
	var hide_top_and_bottom: Array[String] = ["login_ui", "register_ui", "loginui", "registerui", "combat_ui", "combatui"]
	var hide_bottom: Array[String] = ["map_ui", "edit_profile_ui", "mapui", "editprofileui"]

	if top_header:
		if current_scene_name in hide_top_and_bottom:
			top_header.hide()
		else:
			top_header.show()

	if bottom_nav:
		if current_scene_name in hide_top_and_bottom or current_scene_name in hide_bottom:
			bottom_nav.hide()
		else:
			bottom_nav.show()

	if world_map_button:
		if current_scene_name in hide_top_and_bottom or current_scene_name in hide_bottom or (current_scene_name != "game_ui" and current_scene_name != "gameui"):
			world_map_button.hide()
		else:
			world_map_button.show()

	if user_menu_button:
		if current_scene_name in hide_top_and_bottom:
			user_menu_button.hide()
		else:
			user_menu_button.show()

	# Enforce persistent nodes stay on top by moving them to end
	if top_header and top_header.get_parent():
		canvas_layer.move_child(top_header, -1)
	if bottom_nav and bottom_nav.get_parent():
		canvas_layer.move_child(bottom_nav, -1)
	if world_map_button and world_map_button.get_parent():
		canvas_layer.move_child(world_map_button, -1)
	if user_menu_button and user_menu_button.get_parent():
		canvas_layer.move_child(user_menu_button, -1)

func push(scene_name_key: String, params: Dictionary = {}) -> void:
	if not _scenes_map.has(scene_name_key):
		push_error("UIManager: Unknown scene key %s" % scene_name_key)
		return

	# Check if the scene is already at the top of the stack
	if not _menu_stack.is_empty():
		var current_top: String = _menu_stack.back().get_meta("scene_key", _menu_stack.back().name.to_lower())
		if current_top == scene_name_key:
			return # Already on this menu

	var scene_path: String = _scenes_map[scene_name_key]
	var packed_scene: PackedScene = load(scene_path)
	if not packed_scene:
		push_error("UIManager: Failed to load scene %s" % scene_path)
		return

	var instance: Node = packed_scene.instantiate()
	instance.set_meta("scene_key", scene_name_key)

	# If there's an existing scene, hide it
	if not _menu_stack.is_empty():
		_menu_stack.back().hide()

	_menu_stack.append(instance)
	canvas_layer.add_child(instance)

	# Explicitly show the new instance in case the saved .tscn has visible = false
	instance.show()

	# Pass any parameters if the scene has an init function
	if params and instance.has_method("init_scene"):
		instance.init_scene(params)

	_update_overlays()

func pop() -> void:
	if _menu_stack.size() <= 1:
		push_warning("UIManager: Cannot pop the last scene in the stack.")
		return

	var top_scene: Node = _menu_stack.pop_back()
	top_scene.queue_free()

	var new_top: Node = _menu_stack.back()
	new_top.show()

	_update_overlays()

func pop_to_root() -> void:
	if _menu_stack.is_empty():
		return

	while _menu_stack.size() > 1:
		var scene: Node = _menu_stack.pop_back()
		scene.queue_free()

	var root_scene: Node = _menu_stack.back()
	root_scene.show()

	_update_overlays()

func set_root(scene_name_key: String, params: Dictionary = {}) -> void:
	# If the requested scene is already the root and the only one in the stack, do nothing
	if _menu_stack.size() == 1:
		var current_root_key = _menu_stack[0].get_meta("scene_key", "")
		if current_root_key == scene_name_key:
			return

	# Clear the stack entirely
	for scene in _menu_stack:
		scene.queue_free()
	_menu_stack.clear()

	# Push the new root
	push(scene_name_key, params)
