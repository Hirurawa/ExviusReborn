extends Control

const UNIT_SCENE: PackedScene = preload("res://features/shared/Unit.tscn")

@onready var vbox_container: VBoxContainer = $VBoxContainer
@onready var title_label: Label = $VBoxContainer/UnitNamebgChara/Title
@onready var units_scroll_container: ScrollContainer = $VBoxContainer/ScrollContainer
@onready var units_list_container: GridContainer = $VBoxContainer/ScrollContainer/UnitsListContainer

@onready var back_button: TextureButton = $VBoxContainer/UnitNamebgChara/BackButton

@onready var action_row: TextureRect = $VBoxContainer/unit_mix_ui_bg_0
@onready var clear_button: TextureButton = $VBoxContainer/unit_mix_ui_bg_0/unit_mix_button_clear
@onready var confirm_button: TextureButton = $VBoxContainer/unit_mix_ui_bg_0/unit_mix_button_union

var mode: String = "view"
var target_party_index: int = 0
var target_slot_index: int = 0
var exclude_list: Array = []
var pre_selected_units: Array = []
var selection_callback: Callable = Callable()

const GRID_COLUMNS: int = 5
const UNIT_CELL_W: int = 128
const UNIT_CELL_H: int = 164
const PEDESTAL_BOTTOM_MARGIN: int = 2
const UNIT_SIDE_PADDING: int = 4
const V_SCROLLBAR_MIN_W: float = 12.0
const MAX_MATERIAL_SELECTION: int = 5

signal unit_selected(unit_inst: Dictionary)
signal materials_selected(units_array: Array)

var _texture_cache: Dictionary = {}
var _exclude_instance_id_set: Dictionary = {}
var _selected_units_map: Dictionary = {}
var _material_checkboxes: Dictionary = {}
var _suppress_checkbox_signal: bool = false

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _get_pedestal_texture(rarity: int) -> Texture2D:
	var candidate_paths: Array[String] = [
		"res://assets/ui/unit/unit_charastand_rare%s_small.tres" % rarity,
		"res://assets/ui/unit/unit_charastand_rare%s_small.png" % rarity,
		"res://assets/ui/unit/unit_charastand_small.tres",
		"res://assets/ui/unit/unit_charastand_small.png"
	]

	for path in candidate_paths:
		if ResourceLoader.exists(path):
			return _get_dynamic_texture(path)

	return null

func init_scene(params: Dictionary) -> void:
	if params.has("mode"):
		mode = params.mode
	if params.has("party_index"):
		target_party_index = params.party_index
	if params.has("slot_index"):
		target_slot_index = params.slot_index
	if params.has("exclude_list") and params.exclude_list is Array:
		exclude_list = params.exclude_list.duplicate()
	if params.has("pre_selected_units") and params.pre_selected_units is Array:
		pre_selected_units = params.pre_selected_units.duplicate(true)
	if params.has("selection_callback") and params.selection_callback is Callable:
		selection_callback = params.selection_callback

	_rebuild_exclude_set()
	_seed_preselected_materials()
	_apply_scene_params()

func _apply_scene_params() -> void:
	if not is_node_ready():
		call_deferred("_apply_scene_params")
		return

	_update_mode_ui()
	_refresh_units_list(DataManager.owned_units_ids)

func _rebuild_exclude_set() -> void:
	_exclude_instance_id_set.clear()
	for entry in exclude_list:
		if entry is String and entry != "":
			_exclude_instance_id_set[entry] = true
		elif entry is Dictionary:
			var instance_id: String = str(entry.get("instance_id", ""))
			if instance_id != "":
				_exclude_instance_id_set[instance_id] = true

func _seed_preselected_materials() -> void:
	_selected_units_map.clear()
	if mode != "enhance_material_selection":
		return

	for entry in pre_selected_units:
		if not (entry is Dictionary):
			continue
		var instance_id: String = str(entry.get("instance_id", ""))
		if instance_id == "":
			continue
		if _exclude_instance_id_set.has(instance_id):
			continue
		if _selected_units_map.size() >= MAX_MATERIAL_SELECTION:
			break
		_selected_units_map[instance_id] = entry

func _ready() -> void:
	units_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	units_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	
	back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	back_button.pressed.connect(_on_back_pressed)

	clear_button.mouse_filter = Control.MOUSE_FILTER_STOP
	clear_button.pressed.connect(_on_clear_material_selection)

	confirm_button.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_button.pressed.connect(_on_confirm_material_selection)
	
	_update_mode_ui()
	_configure_vertical_scrollbar()
	units_list_container.columns = GRID_COLUMNS
	units_scroll_container.resized.connect(_on_scroll_metrics_changed)
	DataManager.units_updated.connect(_on_units_updated)
	_refresh_units_list(DataManager.owned_units_ids)

func _on_back_pressed() -> void:
	UIManager.pop()

func _update_mode_ui() -> void:
	if title_label == null:
		return

	match mode:
		"enhance_base_selection":
			title_label.text = "Select Base"
		"enhance_material_selection":
			title_label.text = "Select Material Units"
		_:
			title_label.text = "View Units"

	if action_row == null:
		return

	# Always show action row in selector modes
	var selector_mode: bool = mode == "select" or mode == "enhance_material_selection"
	action_row.visible = selector_mode

func _on_clear_material_selection() -> void:
	_selected_units_map.clear()
	for key in _material_checkboxes.keys():
		var check_box: CheckBox = _material_checkboxes.get(key, null) as CheckBox
		if check_box != null:
			_set_checkbox_state(check_box, false)

func _on_units_updated(units: Array) -> void:
	_refresh_units_list(units)

func _refresh_units_list(owned_units_ids: Array) -> void:
	var cell_width: int = _get_effective_cell_width()
	units_list_container.columns = GRID_COLUMNS
	_material_checkboxes.clear()

	for child in units_list_container.get_children():
		child.queue_free()

	if owned_units_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No units owned."
		units_list_container.add_child(empty_label)
		return

	for unit_inst in owned_units_ids:
		if not unit_inst is Dictionary:
			continue

		var unit_instance_id: String = str(unit_inst.get("instance_id", ""))
		if not _should_display_unit(unit_instance_id):
			continue

		var unit_id: String = unit_inst.get("unit_id", "")
		var unit_data: Dictionary = DataManager.game_data_units.get(unit_id, {})
		
		# Keep five columns and shrink cell width only when viewport is tight.
		var container: Control = Control.new()
		container.custom_minimum_size = Vector2(cell_width, UNIT_CELL_H)
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_FILL
		container.clip_contents = true

		# Load textures for the Unit scene and let it fit itself inside this cell.
		var sprite_texture: Texture2D = null
		var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
		if ResourceLoader.exists(img_path):
			sprite_texture = _get_dynamic_texture(img_path)

		var pedestal_texture: Texture2D = _get_pedestal_texture(unit_inst.get("rarity", 1))

		var visual_area_h: int = UNIT_CELL_H

		var visual_container: Control = Control.new()
		visual_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visual_container.clip_contents = true

		if sprite_texture and pedestal_texture:
			var unit_visual: Control = UNIT_SCENE.instantiate() as Control
			if unit_visual:
				unit_visual.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
				visual_container.add_child(unit_visual)
				if unit_visual.has_method("setup_in_cell"):
					unit_visual.call(
						"setup_in_cell",
						sprite_texture,
						pedestal_texture,
						float(cell_width),
						float(visual_area_h),
						float(UNIT_SIDE_PADDING),
						float(PEDESTAL_BOTTOM_MARGIN),
						str(unit_data.get("name", "Unknown"))
					)
				else:
					unit_visual.call_deferred("setup", sprite_texture, pedestal_texture)

		container.add_child(visual_container)

		var click_btn: Button = Button.new()
		click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		click_btn.pressed.connect(_on_unit_clicked.bind(unit_inst))
		click_btn.z_index = 18
		container.add_child(click_btn)

		if mode == "enhance_material_selection":
			var check_box: CheckBox = CheckBox.new()
			check_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			check_box.position = Vector2(4, 4)
			check_box.z_index = 25
			check_box.mouse_filter = Control.MOUSE_FILTER_STOP
			var checked: bool = _selected_units_map.has(unit_instance_id)
			_set_checkbox_state(check_box, checked)
			check_box.toggled.connect(_on_material_checkbox_toggled.bind(unit_inst))
			container.add_child(check_box)
			_material_checkboxes[unit_instance_id] = check_box

		units_list_container.add_child(container)

func _should_display_unit(unit_instance_id: String) -> bool:
	if unit_instance_id == "":
		return false
	return not _exclude_instance_id_set.has(unit_instance_id)

func _set_checkbox_state(check_box: CheckBox, state: bool) -> void:
	_suppress_checkbox_signal = true
	check_box.button_pressed = state
	_suppress_checkbox_signal = false

func _on_material_checkbox_toggled(checked: bool, unit_inst: Dictionary) -> void:
	if _suppress_checkbox_signal:
		return
	_apply_material_toggle(unit_inst, checked)

func _apply_material_toggle(unit_inst: Dictionary, checked: bool) -> void:
	var instance_id: String = str(unit_inst.get("instance_id", ""))
	if instance_id == "":
		return

	if checked:
		if _selected_units_map.has(instance_id):
			return
		if _selected_units_map.size() >= MAX_MATERIAL_SELECTION:
			var check_box: CheckBox = _material_checkboxes.get(instance_id, null) as CheckBox
			if check_box != null:
				_set_checkbox_state(check_box, false)
			return
		_selected_units_map[instance_id] = unit_inst
		return

	_selected_units_map.erase(instance_id)

func _on_confirm_material_selection() -> void:
	if mode != "enhance_material_selection":
		return

	var ordered_selection: Array = []
	for entry in DataManager.owned_units_ids:
		if not (entry is Dictionary):
			continue
		var instance_id: String = str(entry.get("instance_id", ""))
		if instance_id == "":
			continue
		if _selected_units_map.has(instance_id):
			ordered_selection.append(entry)

	UIManager.pop()
	materials_selected.emit(ordered_selection)
	if selection_callback.is_valid():
		selection_callback.call(ordered_selection)

func _on_scroll_metrics_changed() -> void:
	_configure_vertical_scrollbar()
	call_deferred("_rebuild_for_layout_change")

func _configure_vertical_scrollbar() -> void:
	var vertical_bar: VScrollBar = units_scroll_container.get_v_scroll_bar()
	if vertical_bar == null:
		return

	vertical_bar.show()
	vertical_bar.custom_minimum_size.x = maxf(V_SCROLLBAR_MIN_W, vertical_bar.custom_minimum_size.x)

func _get_effective_cell_width() -> int:
	var column_spacing: float = float(units_list_container.get_theme_constant("h_separation"))
	var usable_width: float = units_scroll_container.size.x

	var vertical_bar: VScrollBar = units_scroll_container.get_v_scroll_bar()
	if vertical_bar:
		var reserved_scroll_w: float = maxf(V_SCROLLBAR_MIN_W, vertical_bar.custom_minimum_size.x)
		usable_width -= reserved_scroll_w

	if usable_width <= 0.0:
		return UNIT_CELL_W

	var spacing_total: float = column_spacing * float(GRID_COLUMNS - 1)
	var available_for_cells: float = maxf(1.0, usable_width - spacing_total)
	var fitted_cell_width: int = int(floor(available_for_cells / float(GRID_COLUMNS)))
	return maxi(1, mini(UNIT_CELL_W, fitted_cell_width))

func _rebuild_for_layout_change() -> void:
	_refresh_units_list(DataManager.owned_units_ids)

func _on_unit_clicked(unit_inst: Dictionary) -> void:
	if mode == "view":
		UIManager.push("unit_detail_ui", {"unit_inst": unit_inst})
	elif mode == "select":
		unit_selected.emit(unit_inst)
		DataManager.assign_unit_to_party(target_party_index, target_slot_index, unit_inst.instance_id)
		UIManager.pop()
	elif mode == "enhance_base_selection":
		unit_selected.emit(unit_inst)
		UIManager.pop()
		if selection_callback.is_valid():
			selection_callback.call(unit_inst)
	elif mode == "enhance_material_selection":
		var instance_id: String = str(unit_inst.get("instance_id", ""))
		var check_box: CheckBox = _material_checkboxes.get(instance_id, null) as CheckBox
		if check_box == null:
			return
		var next_state: bool = not check_box.button_pressed
		_set_checkbox_state(check_box, next_state)
		_apply_material_toggle(unit_inst, next_state)
