extends Control

@onready var map_scroll: ScrollContainer = $VBoxContainer/MapScrollContainer
@onready var map_sizer: Control = $VBoxContainer/MapScrollContainer/MapSizer
@onready var map_content: Control = $VBoxContainer/MapScrollContainer/MapSizer/MapContent
@onready var map_image: TextureRect = $VBoxContainer/MapScrollContainer/MapSizer/MapContent/MapImage

@onready var map_world_option: OptionButton = $VBoxContainer/HBoxContainer/WorldOptionButton
@onready var map_region_option: OptionButton = $VBoxContainer/HBoxContainer/RegionOptionButton
@onready var map_subregion_option: OptionButton = $VBoxContainer/HBoxContainer/SubregionOptionButton
@onready var map_back_button: Button = $VBoxContainer/TopBar/BackButton

@onready var mission_details_popup: PopupPanel = $MissionDetailsPopup
@onready var mission_dungeon_name: Label = $MissionDetailsPopup/VBoxContainer/DungeonNameLabel
@onready var missions_list_container: VBoxContainer = $MissionDetailsPopup/VBoxContainer/ScrollContainer/MissionsListContainer

var map_zoom_level: float = 1.0
var _is_panning_map: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO

var current_selected_world: String = ""
var current_selected_region: String = ""
var current_selected_subregion: String = ""
var current_selected_dungeon_id: String = ""

var _texture_cache: Dictionary = {}

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _ready() -> void:
	map_back_button.pressed.connect(func(): UIManager.pop())
	map_world_option.item_selected.connect(_on_map_world_selected)
	map_region_option.item_selected.connect(_on_map_region_selected)
	map_subregion_option.item_selected.connect(_on_map_subregion_selected)
	map_scroll.gui_input.connect(_on_map_scroll_gui_input)
	DataManager.dungeon_missions_ready.connect(_on_dungeon_missions_ready)

	_populate_world_options()
	await _apply_latest_cleared_map_selection()
	map_zoom_level = 1.0
	map_content.scale = Vector2(map_zoom_level, map_zoom_level)
	map_sizer.custom_minimum_size = Vector2(2000, 2000) * map_zoom_level

func _apply_latest_cleared_map_selection() -> void:
	var selection: Dictionary = await DataManager.get_latest_cleared_map_selection()
	if selection.is_empty():
		return

	var world_id: String = str(selection.get("world_id", ""))
	var region_id: String = str(selection.get("region_id", ""))
	var subregion_id: String = str(selection.get("subregion_id", ""))

	var world_idx: int = _select_option_by_metadata(map_world_option, world_id)
	if world_idx == -1:
		return
	_on_map_world_selected(world_idx)

	var region_idx: int = _select_option_by_metadata(map_region_option, region_id)
	if region_idx == -1:
		return
	_on_map_region_selected(region_idx)

	var subregion_idx: int = _select_option_by_metadata(map_subregion_option, subregion_id)
	if subregion_idx == -1:
		return
	_on_map_subregion_selected(subregion_idx)

func _select_option_by_metadata(option_button: OptionButton, metadata_id: String) -> int:
	if metadata_id == "":
		return -1

	for idx in range(option_button.get_item_count()):
		if str(option_button.get_item_metadata(idx)) == metadata_id:
			option_button.select(idx)
			return idx

	return -1

func _on_map_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_panning_map = true
				_last_mouse_pos = event.global_position
			else:
				_is_panning_map = false
		elif event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var old_zoom = map_zoom_level
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				map_zoom_level = clamp(map_zoom_level + 0.1, 0.5, 3.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				map_zoom_level = clamp(map_zoom_level - 0.1, 0.5, 3.0)

			if old_zoom != map_zoom_level:
				map_content.scale = Vector2(map_zoom_level, map_zoom_level)
				map_sizer.custom_minimum_size = Vector2(2000, 2000) * map_zoom_level
			map_scroll.accept_event()

	elif event is InputEventMouseMotion and _is_panning_map:
		map_scroll.scroll_horizontal -= int(event.relative.x)
		map_scroll.scroll_vertical -= int(event.relative.y)

func _populate_world_options() -> void:
	map_world_option.clear()
	map_region_option.clear()
	map_subregion_option.clear()

	for child in map_content.get_children():
		if child != map_image:
			child.queue_free()

	map_world_option.add_item("Select a World", 0)
	map_world_option.set_item_metadata(0, "")

	var idx = 1
	for world_id in DataManager.game_data_worlds.keys():
		var world_data = DataManager.game_data_worlds[world_id]
		var world_name = "Unknown World"
		if world_data.has("names") and world_data.names.size() > 0 and world_data.names[0]:
			world_name = world_data.names[0]
		map_world_option.add_item(world_name, idx)
		map_world_option.set_item_metadata(idx, world_id)
		idx += 1

func _on_map_world_selected(index: int) -> void:
	map_region_option.clear()
	map_subregion_option.clear()
	current_selected_world = map_world_option.get_item_metadata(index)

	for child in map_content.get_children():
		if child != map_image:
			child.queue_free()

	if current_selected_world == "":
		return

	var world_data = DataManager.game_data_worlds.get(current_selected_world, {})
	var regions = world_data.get("regions", {})

	map_region_option.add_item("Select a Region", 0)
	map_region_option.set_item_metadata(0, "")

	var idx = 1
	for region_id in regions.keys():
		var region_data = regions[region_id]
		var region_name = "Unknown Region"
		if region_data.has("names") and region_data.names.size() > 0 and region_data.names[0]:
			region_name = region_data.names[0]
		map_region_option.add_item(region_name, idx)
		map_region_option.set_item_metadata(idx, region_id)
		idx += 1

func _on_map_region_selected(index: int) -> void:
	map_subregion_option.clear()
	current_selected_region = map_region_option.get_item_metadata(index)

	for child in map_content.get_children():
		if child != map_image:
			child.queue_free()

	if current_selected_region == "" or current_selected_world == "":
		return

	var world_data = DataManager.game_data_worlds.get(current_selected_world, {})
	var regions = world_data.get("regions", {})
	var region_data = regions.get(current_selected_region, {})
	var subregions = region_data.get("subregions", {})

	map_subregion_option.add_item("Select a Subregion", 0)
	map_subregion_option.set_item_metadata(0, "")

	var idx = 1
	for subregion_id in subregions.keys():
		var subregion_data = subregions[subregion_id]
		var subregion_name = "Unknown Subregion"
		if subregion_data.has("names") and subregion_data.names.size() > 0 and subregion_data.names[0]:
			subregion_name = subregion_data.names[0]
		map_subregion_option.add_item(subregion_name, idx)
		map_subregion_option.set_item_metadata(idx, subregion_id)
		idx += 1

func _on_map_subregion_selected(index: int) -> void:
	current_selected_subregion = map_subregion_option.get_item_metadata(index)

	for child in map_content.get_children():
		if child != map_image:
			child.queue_free()

	if current_selected_subregion == "" or current_selected_region == "" or current_selected_world == "":
		return

	var world_data = DataManager.game_data_worlds.get(current_selected_world, {})
	var regions = world_data.get("regions", {})
	var region_data = regions.get(current_selected_region, {})
	var subregions = region_data.get("subregions", {})
	var subregion_data = subregions.get(current_selected_subregion, {})
	var dungeons = subregion_data.get("dungeons", {})

	var dungeon_ids = []
	if dungeons is Dictionary:
		dungeon_ids = dungeons.keys()
	elif dungeons is Array:
		dungeon_ids = dungeons
	elif dungeons is String:
		dungeon_ids = [dungeons]

	for dungeon_id in dungeon_ids:
		var dungeon_data = DataManager.game_data_dungeons.get(str(dungeon_id), {})
		if dungeon_data.is_empty():
			continue

		var pos: Array = dungeon_data.get("position", [0, 0])
		var x: int = pos[0]
		var y: int = pos[1]

		var icon_name: String = dungeon_data.get("icon", "")
		var icon_path: String = "res://assets/map_icons/" + icon_name

		var btn: TextureButton = TextureButton.new()
		var tex: Texture2D = _get_dynamic_texture(icon_path)
		if not tex:
			tex = _get_dynamic_texture("res://icon.svg") # Fallback

		if tex:
			btn.texture_normal = tex
			btn.position = Vector2(x, y)

			var lbl = Label.new()
			var d_names = dungeon_data.get("names", [])
			if d_names.size() > 0 and d_names[0]:
				lbl.text = d_names[0]
			else:
				lbl.text = "Unknown Dungeon"

			lbl.position = Vector2(-lbl.get_minimum_size().x/2 + btn.size.x/2, btn.size.y)
			lbl.add_theme_font_size_override("font_size", 14)
			lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
			lbl.add_theme_constant_override("outline_size", 4)
			btn.add_child(lbl)

			btn.pressed.connect(_on_dungeon_clicked.bind(str(dungeon_id)))
			map_content.add_child(btn)

func _on_dungeon_clicked(dungeon_id: String) -> void:
	current_selected_dungeon_id = dungeon_id
	var dungeon_data = DataManager.game_data_dungeons.get(dungeon_id, {})
	var d_names = dungeon_data.get("names", [])
	if d_names.size() > 0 and d_names[0]:
		mission_dungeon_name.text = d_names[0]
	else:
		mission_dungeon_name.text = "Unknown Dungeon"

	for child in missions_list_container.get_children():
		child.queue_free()

	var dungeon_missions = dungeon_data.get("missions", {})
	var mission_ids = []
	if dungeon_missions is Dictionary:
		mission_ids = dungeon_missions.keys()
	elif dungeon_missions is Array:
		mission_ids = dungeon_missions
	elif dungeon_missions is String:
		mission_ids = [dungeon_missions]

	for mission_id in mission_ids:
		var mission_data = DataManager.game_data_missions.get(str(mission_id), {})
		if mission_data.is_empty():
			continue

		var vbox = VBoxContainer.new()

		var name_lbl = Label.new()
		name_lbl.text = mission_data.get("name", "Unknown Mission")
		name_lbl.add_theme_font_size_override("font_size", 16)
		vbox.add_child(name_lbl)

		var cost_lbl = Label.new()
		cost_lbl.text = "Cost: %d %s" % [mission_data.get("cost", 0), mission_data.get("cost_type", "NRG")]
		cost_lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(cost_lbl)

		var sep = HSeparator.new()
		vbox.add_child(sep)

		var actions_hbox = HBoxContainer.new()
		var btn_start = Button.new()
		btn_start.text = "Start"
		btn_start.pressed.connect(_on_start_mission_pressed.bind(str(mission_id)))
		actions_hbox.add_child(btn_start)
		vbox.add_child(actions_hbox)

		missions_list_container.add_child(vbox)

	mission_details_popup.popup_centered()

	# Lazy load actual mission data
	DataManager.request_dungeon_missions(mission_ids)

func _on_dungeon_missions_ready(mission_ids: Array) -> void:
	if not mission_details_popup.visible:
		return # Closed before loading

	for child in missions_list_container.get_children():
		child.queue_free()

	for mission_id in mission_ids:
		var mission_data = DataManager.game_data_missions.get(str(mission_id), {})
		if mission_data.is_empty():
			continue

		var vbox = VBoxContainer.new()

		var name_lbl = Label.new()
		name_lbl.text = mission_data.get("name", "Unknown Mission")
		name_lbl.add_theme_font_size_override("font_size", 16)
		vbox.add_child(name_lbl)

		var cost_lbl = Label.new()
		cost_lbl.text = "Cost: %d %s" % [mission_data.get("cost", 0), mission_data.get("cost_type", "NRG")]
		cost_lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(cost_lbl)

		var challenges = mission_data.get("challenges", [])
		if challenges.size() > 0:
			var ch_lbl = Label.new()
			ch_lbl.text = "Challenges:"
			ch_lbl.add_theme_font_size_override("font_size", 12)
			vbox.add_child(ch_lbl)
			for ch in challenges:
				var ch_item_lbl = Label.new()
				ch_item_lbl.text = "- " + ch.get("string", "")
				ch_item_lbl.add_theme_font_size_override("font_size", 10)
				vbox.add_child(ch_item_lbl)

		var sep = HSeparator.new()
		vbox.add_child(sep)

		var actions_hbox = HBoxContainer.new()
		var btn_start = Button.new()
		btn_start.text = "Start"
		btn_start.pressed.connect(_on_start_mission_pressed.bind(str(mission_id)))
		actions_hbox.add_child(btn_start)
		vbox.add_child(actions_hbox)

		missions_list_container.add_child(vbox)


func _on_start_mission_pressed(mission_id: String) -> void:
	var result: Dictionary = await DataManager.request_start_mission(mission_id)

	if result.get("success") == true:
		mission_details_popup.hide()
		UIManager.push("combat_ui", {"mission_id": mission_id, "dungeon_id": current_selected_dungeon_id})
	else:
		var error_msg = result.get("error", "Unknown error occurred")
		var error_dialog = AcceptDialog.new()
		error_dialog.dialog_text = error_msg
		error_dialog.title = "Mission Failed to Start"
		add_child(error_dialog)
		error_dialog.popup_centered()
		error_dialog.confirmed.connect(func(): error_dialog.queue_free())
