extends Node2D

# Root controller for the town map scene. Configures the TileMap based on
# the requested town id and verifies the necessary data folder exists.

const TOWN_DATA_ROOT: String = "res://assets/town_data"

@onready var tile_map: TileMap = $TileMap

var current_town_id: String = ""
# Tracks whether we toggled the parent CanvasLayer's follow_viewport_enabled
# so we can restore it on exit. UIManager parents scenes under a CanvasLayer,
# and Camera2D only transforms the underlying viewport canvas — not custom
# CanvasLayers — unless follow_viewport_enabled is true.
var _canvas_layer_follow_was: bool = false
var _canvas_layer_touched: bool = false

# Locally-owned CanvasLayer for the leave-town confirmation popup. We can't
# reuse UIManager's CanvasLayer because we toggled follow_viewport_enabled
# on it (the dialog would scroll with the camera). A non-following layer
# keeps the dialog screen-locked.
var _ui_layer: CanvasLayer = null
var _leave_dialog: ConfirmationDialog = null

func _ready() -> void:
	var parent_layer := get_parent() as CanvasLayer
	if parent_layer:
		_canvas_layer_follow_was = parent_layer.follow_viewport_enabled
		parent_layer.follow_viewport_enabled = true
		_canvas_layer_touched = true

	# Spawn the minimap here (town-only) rather than in tile_map.gd, so
	# reusing TileMap in non-town scenes (e.g. Event.tscn) doesn't pull
	# a minimap into their HUD. minimap.gd is a CanvasLayer that
	# self-registers in the "minimap" group; tile_map.gd's bake and
	# player.gd's marker update both find it via that group.
	if get_node_or_null("Minimap") == null:
		var mm: Node = preload("res://features/town/minimap.gd").new()
		mm.name = "Minimap"
		add_child(mm)
		tile_map.call_deferred("_update_minimap")

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "TownMapUILayer"
	# Sit above the world map but stay screen-locked.
	_ui_layer.layer = 10
	add_child(_ui_layer)

	_leave_dialog = ConfirmationDialog.new()
	_leave_dialog.title = "Leave Town"
	_leave_dialog.dialog_text = "Leave this town?"
	_leave_dialog.ok_button_text = "Yes"
	_leave_dialog.cancel_button_text = "No"
	_leave_dialog.exclusive = false
	_leave_dialog.confirmed.connect(_on_leave_confirmed)
	_ui_layer.add_child(_leave_dialog)

	var toggle_minimap_btn := get_node_or_null("HUDLayer/HUD/ToggleMinimap") as BaseButton
	if toggle_minimap_btn and not toggle_minimap_btn.pressed.is_connected(_on_toggle_minimap_pressed):
		toggle_minimap_btn.pressed.connect(_on_toggle_minimap_pressed)

	var town_menu_btn := get_node_or_null("HUDLayer/HUD/TownMenu") as BaseButton
	if town_menu_btn and not town_menu_btn.pressed.is_connected(_prompt_leave_town):
		town_menu_btn.pressed.connect(_prompt_leave_town)

func _on_toggle_minimap_pressed() -> void:
	var mm := get_tree().get_first_node_in_group("minimap")
	if mm == null:
		return
	mm.visible = not mm.visible

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_prompt_leave_town()
		get_viewport().set_input_as_handled()

func _prompt_leave_town() -> void:
	if not _leave_dialog:
		return
	if _leave_dialog.visible:
		return
	var town_name: String = _resolve_town_name(current_town_id)
	if town_name != "":
		_leave_dialog.dialog_text = "Leave %s?" % town_name
	else:
		_leave_dialog.dialog_text = "Leave this town?"
	_leave_dialog.popup_centered()

func _resolve_town_name(town_id: String) -> String:
	if town_id == "":
		return ""
	return str(GameDatabase.get_town(town_id).get("townName", ""))

func _on_leave_confirmed() -> void:
	UIManager.pop()

func _exit_tree() -> void:
	if _canvas_layer_touched:
		var parent_layer := get_parent() as CanvasLayer
		if parent_layer:
			parent_layer.follow_viewport_enabled = _canvas_layer_follow_was

func init_scene(params: Dictionary) -> void:
	var town_id: String = str(params.get("town_id", ""))
	if town_id == "":
		push_error("TownMap: init_scene called without town_id")
		UIManager.pop()
		return
	current_town_id = town_id
	_load_town(town_id)

# The town id (e.g. "1102") is NOT the on-disk folder name. The real folder id
# is encoded in the town's icon (TOWN.iconFile): "map_icon_<digits>.png" ->
# "<digits>00". Returns "" if the town is unknown or its icon doesn't follow the
# expected convention.
func _resolve_town_folder_id(town_id: String) -> String:
	var icon: String = str(GameDatabase.get_town(town_id).get("iconFile", ""))
	if icon == "":
		return ""
	var base: String = icon.get_file().get_basename()
	const PREFIX: String = "map_icon_"
	if not base.begins_with(PREFIX):
		return ""
	return base.substr(PREFIX.length()) + "00"

func _load_town(town_id: String) -> void:
	var folder_id: String = _resolve_town_folder_id(town_id)
	if folder_id == "":
		push_error("TownMap: could not resolve folder id for town %s" % town_id)
		UIManager.pop()
		return

	var town_dir: String = "%s/%s" % [TOWN_DATA_ROOT, folder_id]
	if not DirAccess.dir_exists_absolute(town_dir):
		push_error("Town data folder not found: %s" % town_dir)
		UIManager.pop()
		return

	tile_map.quest_town_id = town_id
	tile_map.load_town(folder_id)
