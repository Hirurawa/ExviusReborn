extends Node

var canvas_layer: CanvasLayer
var _menu_stack: Array[Node] = []

var top_header: Node = null
var bottom_nav: Node = null
var home_buttons: Node = null

# Add standard menu mappings for easier instancing
var _scenes_map: Dictionary = {
	"login_ui": "res://features/auth/LoginUI.tscn",
	"game_ui": "res://features/shared/GameUI.tscn",
	"edit_profile_ui": "res://features/outgame/profile/EditProfileUI.tscn",
	"shop_ui": "res://features/outgame/shop/ShopUI.tscn",
	"map_ui": "res://features/outgame/map/MapUI.tscn",
	"units_ui": "res://features/outgame/units/UnitsUI.tscn",
	"enhance_ui": "res://features/outgame/units/Enhance.tscn",
	"awaken_ui": "res://features/outgame/units/UnitAwakening.tscn",
	"unit_selector_ui": "res://features/outgame/units/UnitSelectorUI.tscn",
	"unit_stats_popup": "res://features/outgame/units/UnitStatsPopup.tscn",
	"unit_detail_ui": "res://features/outgame/units/UnitDetail.tscn",
	"items_ui": "res://features/outgame/inventory/ItemsUI.tscn",
	"item_category_list_ui": "res://features/outgame/inventory/ItemCategoryListUI.tscn",
	"friends_ui": "res://features/outgame/friends/FriendsUI.tscn",
	"summon_ui": "res://features/outgame/summon/SummonUI.tscn",
	"craft_ui": "res://features/outgame/craft/Craft.tscn",
	"craft_equipment_ui": "res://features/outgame/craft/CraftEquipment.tscn",
	"craft_item_ui": "res://features/outgame/craft/CraftItem.tscn",
	"craft_ability_ui": "res://features/outgame/craft/CraftAbility.tscn",
	"espers_ui": "res://features/outgame/espers/EspersUI.tscn",
	"esper_detail_ui": "res://features/outgame/espers/EsperDetailUI.tscn",
	"summon_board_ui": "res://features/outgame/espers/SummonBoardUI.tscn",
	"esper_enhancement_ui": "res://features/outgame/espers/EsperEnhancementUI.tscn",
	"equip_selection_popup": "res://features/outgame/equipment/EquipSelectionPopup.tscn",
	"combat_ui": "res://features/battle/ui/BattleUI.tscn",
	"town_map_ui": "res://features/town/Map.tscn",
	"settings_ui": "res://features/outgame/profile/SettingsUI.tscn",
	"vortex_dungeon_ui": "res://features/outgame/vortex/vortex_dungeon.tscn"
}

# === BGM routing ===
# Scene key → BGM resource path. Keys not listed fall back to BGM_DEFAULT
# (the standard "main pages" track). Use BGM_NONE to suppress music for a key.
const BGM_LOGIN: String = "res://assets/audio/bgm/la001_prelude.wav"
const BGM_MAIN: String = "res://assets/audio/bgm/la003_mypage_normal1.wav"
const BGM_BATTLE: String = "res://assets/audio/bgm/la005_battle1.wav"
const BGM_MAP: String = "res://assets/audio/bgm/la004_map_world1.wav"
const BGM_NONE: String = ""

var _bgm_for_scene: Dictionary = {
	"login_ui": BGM_LOGIN,
	"combat_ui": BGM_BATTLE,
	"map_ui": BGM_MAP,
	"settings_ui": BGM_NONE,
}

# When true, the next scene transition will not change music. Used so the
# battle-end jingle started in BattleUI is not overwritten by the main-page
# music when we pop back out of combat_ui.
var _suppress_next_bgm_change: bool = false


func _ready() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "UIManagerCanvasLayer"
	add_child(canvas_layer)

	_load_persistent_overlays()

func _load_persistent_overlays() -> void:
	# These will be created in step 2. We'll instance them and set visibility.
	if ResourceLoader.exists("res://features/shared/Header.tscn"):
		var top_scene: PackedScene = preload("res://features/shared/Header.tscn")
		top_header = top_scene.instantiate()
		top_header.hide()
		canvas_layer.add_child(top_header)

	if ResourceLoader.exists("res://features/shared/BottomNav.tscn"):
		var bottom_scene: PackedScene = preload("res://features/shared/BottomNav.tscn")
		bottom_nav = bottom_scene.instantiate()
		bottom_nav.hide()
		canvas_layer.add_child(bottom_nav)

	if ResourceLoader.exists("res://features/shared/HomeButtons.tscn"):
		var home_buttons_scene: PackedScene = preload("res://features/shared/HomeButtons.tscn")
		home_buttons = home_buttons_scene.instantiate()
		home_buttons.hide()
		home_buttons.world_map_pressed.connect(_on_world_map_pressed)
		home_buttons.espers_pressed.connect(_on_espers_pressed)
		home_buttons.craft_pressed.connect(_on_craft_pressed)
		canvas_layer.add_child(home_buttons)

func _on_world_map_pressed() -> void:
	push("map_ui")

func _on_espers_pressed() -> void:
	push("espers_ui")

func _on_craft_pressed() -> void:
	push("craft_ui")

func _update_overlays() -> void:
	if _menu_stack.is_empty():
		return

	var current_scene_name: String = _menu_stack.back().get_meta("scene_key", _menu_stack.back().name.to_lower())

	# Determine overlay visibility based on context
	var hide_top_and_bottom: Array[String] = ["login_ui", "loginui", "combat_ui", "combatui", "town_map_ui", "townmapui", "settings_ui", "settingsui"]
	var hide_bottom: Array[String] = ["map_ui", "edit_profile_ui", "esper_detail_ui", "mapui", "editprofileui", "esperdetailui"]

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

	if home_buttons:
		if current_scene_name in hide_top_and_bottom or current_scene_name in hide_bottom or (current_scene_name != "game_ui" and current_scene_name != "gameui"):
			home_buttons.hide()
		else:
			home_buttons.show()

	# Enforce persistent nodes stay on top by moving them to end
	if top_header and top_header.get_parent():
		canvas_layer.move_child(top_header, -1)
	if bottom_nav and bottom_nav.get_parent():
		canvas_layer.move_child(bottom_nav, -1)
	if home_buttons and home_buttons.get_parent():
		canvas_layer.move_child(home_buttons, -1)

	_update_bgm(current_scene_name)


func _update_bgm(scene_key: String) -> void:
	if _suppress_next_bgm_change:
		_suppress_next_bgm_change = false
		return
	if get_node_or_null("/root/AudioService") == null:
		return
	var path: String = _bgm_for_scene.get(scene_key, BGM_MAIN)
	if path == BGM_NONE:
		return
	AudioService.play_music(path)


## Call from BattleUI right before showing the rewards popup so the next
## UIManager.pop() (which switches back to the main pages) does NOT clobber
## the battle-end jingle.
func suppress_next_bgm_change() -> void:
	_suppress_next_bgm_change = true

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

func get_current_scene() -> Node:
	if _menu_stack.is_empty():
		return null
	return _menu_stack.back()


# === Android / Escape back-button routing ===
#
# Listens for the Android hardware back button (NOTIFICATION_WM_GO_BACK_REQUEST)
# and the desktop ui_cancel action (Escape by default). Finds the current
# scene's back button by name and emits its `pressed` signal so any existing
# handler logic, lambdas, confirmation popups, and back-button SFX all fire
# naturally. Falls back to `pop()` if no back button is found.
#
# Scenes can opt out by setting `set_meta("block_back_request", true)` on
# their root node.

# Same convention used by ButtonSoundInstaller to identify back-style buttons.
const _BACK_NAME_PATTERNS: Array[String] = [
	"back", "close", "cancel", "exit",
]
const _META_BLOCK_BACK: StringName = &"block_back_request"


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _handle_back_request():
			get_viewport().set_input_as_handled()


func _handle_back_request() -> bool:
	var current: Node = get_current_scene()
	if current == null:
		return false

	if current.has_meta(_META_BLOCK_BACK) and bool(current.get_meta(_META_BLOCK_BACK)):
		return false

	var back_button: BaseButton = _find_back_button(current)
	if back_button != null:
		back_button.emit_signal("pressed")
		return true

	if _menu_stack.size() > 1:
		pop()
		return true

	return false


func _find_back_button(node: Node) -> BaseButton:
	if node is BaseButton:
		var btn: BaseButton = node
		if btn.is_visible_in_tree() and not btn.disabled and _is_back_button_name(btn.name):
			return btn
	for child in node.get_children():
		var found: BaseButton = _find_back_button(child)
		if found != null:
			return found
	return null


func _is_back_button_name(node_name: StringName) -> bool:
	var name_lc: String = String(node_name).to_lower()
	for pattern in _BACK_NAME_PATTERNS:
		if name_lc.find(pattern) != -1:
			return true
	return false
