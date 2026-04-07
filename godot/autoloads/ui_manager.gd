extends Node

var canvas_layer: CanvasLayer
var _menu_stack: Array[Node] = []

var top_header: Node = null
var bottom_nav: Node = null
var world_map_button: Node = null
var user_menu_button: Node = null

# Add standard menu mappings for easier instancing
var _scenes_map: Dictionary = {
	"login_ui": "res://ui/login_ui.tscn",
	"register_ui": "res://ui/register_ui.tscn",
	"game_ui": "res://ui/game_ui.tscn",
	"edit_profile_ui": "res://ui/edit_profile_ui.tscn",
	"shop_ui": "res://ui/shop_ui.tscn",
	"map_ui": "res://ui/map_ui.tscn",
	"units_ui": "res://ui/units_ui.tscn",
	"unit_detail_ui": "res://ui/unit_detail_ui.tscn",
	"items_ui": "res://ui/items_ui.tscn",
	"friends_ui": "res://ui/friends_ui.tscn",
	"summon_ui": "res://ui/summon_ui.tscn",
	"equip_selection_popup": "res://ui/equip_selection_popup.tscn"
}

func _ready() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "UIManagerCanvasLayer"
	add_child(canvas_layer)

	_load_persistent_overlays()

func _load_persistent_overlays() -> void:
	# These will be created in step 2. We'll instance them and set visibility.
	if ResourceLoader.exists("res://ui/top_header.tscn"):
		var top_scene = load("res://ui/top_header.tscn")
		top_header = top_scene.instantiate()
		top_header.hide()
		canvas_layer.add_child(top_header)

	if ResourceLoader.exists("res://ui/bottom_nav.tscn"):
		var bottom_scene = load("res://ui/bottom_nav.tscn")
		bottom_nav = bottom_scene.instantiate()
		bottom_nav.hide()
		canvas_layer.add_child(bottom_nav)

	if ResourceLoader.exists("res://ui/world_map_button.tscn"):
		var map_btn_scene = load("res://ui/world_map_button.tscn")
		world_map_button = map_btn_scene.instantiate()
		world_map_button.hide()
		world_map_button.pressed.connect(_on_world_map_pressed)
		canvas_layer.add_child(world_map_button)

	if ResourceLoader.exists("res://ui/user_menu_button.tscn"):
		var user_menu_scene = load("res://ui/user_menu_button.tscn")
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

	var current_scene_name = _menu_stack.back().name.to_lower()

	# Determine overlay visibility based on context
	var hide_top_and_bottom = ["loginui", "registerui"]
	var hide_bottom = ["mapui", "editprofileui"]

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
		if current_scene_name in hide_top_and_bottom or current_scene_name in hide_bottom or current_scene_name != "gameui":
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
		var current_top = _menu_stack.back().name.to_lower()
		var requested = scene_name_key.replace("_", "").to_lower()
		if current_top == requested:
			return # Already on this menu

	var scene_path = _scenes_map[scene_name_key]
	var packed_scene = load(scene_path)
	if not packed_scene:
		push_error("UIManager: Failed to load scene %s" % scene_path)
		return

	var instance = packed_scene.instantiate()

	# If there's an existing scene, hide it
	if not _menu_stack.is_empty():
		_menu_stack.back().hide()

	_menu_stack.append(instance)
	canvas_layer.add_child(instance)

	# Pass any parameters if the scene has an init function
	if params and instance.has_method("init_scene"):
		instance.init_scene(params)

	_update_overlays()

func pop() -> void:
	if _menu_stack.size() <= 1:
		push_warning("UIManager: Cannot pop the last scene in the stack.")
		return

	var top_scene = _menu_stack.pop_back()
	top_scene.queue_free()

	var new_top = _menu_stack.back()
	new_top.show()

	_update_overlays()

func pop_to_root() -> void:
	if _menu_stack.is_empty():
		return

	while _menu_stack.size() > 1:
		var scene = _menu_stack.pop_back()
		scene.queue_free()

	var root_scene = _menu_stack.back()
	root_scene.show()

	_update_overlays()

func set_root(scene_name_key: String, params: Dictionary = {}) -> void:
	# Clear the stack entirely
	for scene in _menu_stack:
		scene.queue_free()
	_menu_stack.clear()

	# Push the new root
	push(scene_name_key, params)
