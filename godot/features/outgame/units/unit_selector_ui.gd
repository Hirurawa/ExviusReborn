extends Control

const UNIT_SCENE: PackedScene = preload("res://features/shared/Unit.tscn")

@onready var vbox_container: VBoxContainer = $VBoxContainer
@onready var title_label: Label = $VBoxContainer/UnitNamebgChara/Title
@onready var units_scroll_container: ScrollContainer = $VBoxContainer/ScrollContainer
@onready var units_list_container: GridContainer = $VBoxContainer/ScrollContainer/UnitsListContainer
@onready var sort_option_button: OptionButton = $VBoxContainer/UnitNamebgChara/SortOptionButton

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
const ENHANCE_MAX_TRUST_VALUE: float = 100.0
const EXP_UNIT_JOB_ID: int = 901
const TRUST_MATERIAL_JOB_ID: int = 903

const SORT_DEFAULT: String = "default"
const SORT_NAME_ASC: String = "name_asc"
const SORT_NAME_DESC: String = "name_desc"
const SORT_LEVEL_ASC: String = "level_asc"
const SORT_LEVEL_DESC: String = "level_desc"
const SORT_RARITY_ASC: String = "rarity_asc"
const SORT_RARITY_DESC: String = "rarity_desc"

signal unit_selected(unit_inst: Dictionary)
signal materials_selected(units_array: Array)

static var _shared_texture_cache: Dictionary = {}
static var _shared_path_exists_cache: Dictionary = {}
static var _shared_pedestal_cache: Dictionary = {}

var _exclude_instance_id_set: Dictionary = {}
var _selected_units_map: Dictionary = {}
var _material_checkboxes: Dictionary = {}
var _suppress_checkbox_signal: bool = false
var _current_sort_mode: String = SORT_DEFAULT
var _has_received_init_params: bool = false
var _has_rendered_once: bool = false
var _refresh_scheduled: bool = false
var _last_effective_cell_width: int = -1

func _get_dynamic_texture(path: String) -> Texture2D:
	if _shared_texture_cache.has(path):
		return _shared_texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_shared_texture_cache[path] = tex
	return tex

func _resource_exists(path: String) -> bool:
	if _shared_path_exists_cache.has(path):
		return bool(_shared_path_exists_cache[path])
	var exists: bool = ResourceLoader.exists(path)
	_shared_path_exists_cache[path] = exists
	return exists

func _get_pedestal_texture(rarity: int) -> Texture2D:
	if _shared_pedestal_cache.has(rarity):
		return _shared_pedestal_cache[rarity]

	var candidate_paths: Array[String] = [
		"res://assets/ui/unit/unit_charastand_rare%s_small.tres" % rarity,
		"res://assets/ui/unit/unit_charastand_rare%s_small.png" % rarity,
		"res://assets/ui/unit/unit_charastand_small.tres",
		"res://assets/ui/unit/unit_charastand_small.png"
	]

	for path in candidate_paths:
		if _resource_exists(path):
			var pedestal_texture: Texture2D = _get_dynamic_texture(path)
			_shared_pedestal_cache[rarity] = pedestal_texture
			return pedestal_texture

	_shared_pedestal_cache[rarity] = null
	return null

func init_scene(params: Dictionary) -> void:
	_has_received_init_params = true
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
	_request_units_list_refresh()

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
		if _is_max_trust_playable_material(entry):
			continue
		if _selected_units_map.size() >= MAX_MATERIAL_SELECTION:
			break
		_selected_units_map[instance_id] = entry

func _ready() -> void:
	units_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	units_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_setup_sort_dropdown()
	
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
	UnitService.units_updated.connect(_on_units_updated)
	call_deferred("_refresh_after_ready_without_params")

func _refresh_after_ready_without_params() -> void:
	if _has_received_init_params:
		return
	_request_units_list_refresh()

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
	_request_units_list_refresh()

func _request_units_list_refresh() -> void:
	if _refresh_scheduled:
		return
	_refresh_scheduled = true
	call_deferred("_perform_units_list_refresh")

func _perform_units_list_refresh() -> void:
	_refresh_scheduled = false
	if not is_node_ready():
		_request_units_list_refresh()
		return
	_refresh_units_list(UnitService.owned_units_ids)

func _refresh_units_list(owned_units_ids: Array) -> void:
	var sorted_units: Array = _sort_units_for_display(owned_units_ids)
	var cell_width: int = _get_effective_cell_width()
	_last_effective_cell_width = cell_width
	_has_rendered_once = true
	units_list_container.columns = GRID_COLUMNS
	_material_checkboxes.clear()

	for child in units_list_container.get_children():
		child.queue_free()

	if sorted_units.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No units owned."
		units_list_container.add_child(empty_label)
		return

	for unit_inst in sorted_units:
		if not unit_inst is Dictionary:
			continue

		var unit_instance_id: String = str(unit_inst.get("instance_id", ""))
		if not _should_display_unit(unit_instance_id):
			continue

		var unit_id: String = unit_inst.get("unit_id", "")
		var unit_data: Dictionary = StaticData.game_data_units.get(unit_id, {})
		var is_disabled_max_trust_material: bool = _is_max_trust_playable_material(unit_inst)
		if is_disabled_max_trust_material:
			_selected_units_map.erase(unit_instance_id)
		
		# Keep five columns and shrink cell width only when viewport is tight.
		var container: Control = Control.new()
		container.custom_minimum_size = Vector2(cell_width, UNIT_CELL_H)
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_FILL
		container.clip_contents = true

		# Load textures for the Unit scene and let it fit itself inside this cell.
		var sprite_texture: Texture2D = null
		var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
		if _resource_exists(img_path):
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
		if is_disabled_max_trust_material:
			container.modulate = Color(1.0, 1.0, 1.0, 0.45)

		if mode == "enhance_material_selection":
			var check_box: CheckBox = CheckBox.new()
			check_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			check_box.position = Vector2(4, 4)
			check_box.z_index = 25
			check_box.mouse_filter = Control.MOUSE_FILTER_STOP
			var checked: bool = _selected_units_map.has(unit_instance_id)
			_set_checkbox_state(check_box, checked)
			check_box.disabled = is_disabled_max_trust_material
			if is_disabled_max_trust_material:
				check_box.tooltip_text = "Cannot use a playable unit at 100% trust as enhancement material"
			check_box.toggled.connect(_on_material_checkbox_toggled.bind(unit_inst))
			container.add_child(check_box)
			_material_checkboxes[unit_instance_id] = check_box

			if is_disabled_max_trust_material:
				var badge: Label = Label.new()
				badge.text = "MAX TRUST"
				badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
				badge.position = Vector2(-96, 6)
				badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				badge.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
				badge.add_theme_constant_override("outline_size", 2)
				badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
				badge.z_index = 30
				container.add_child(badge)

		units_list_container.add_child(container)

func _setup_sort_dropdown() -> void:
	if sort_option_button == null:
		return

	sort_option_button.clear()
	_add_sort_option("Sort: Default", SORT_DEFAULT)
	_add_sort_option("Name A->Z", SORT_NAME_ASC)
	_add_sort_option("Name Z->A", SORT_NAME_DESC)
	_add_sort_option("Level Low->High", SORT_LEVEL_ASC)
	_add_sort_option("Level High->Low", SORT_LEVEL_DESC)
	_add_sort_option("Rarity Low->High", SORT_RARITY_ASC)
	_add_sort_option("Rarity High->Low", SORT_RARITY_DESC)
	_select_sort_option_by_mode(_current_sort_mode)

	var selection_cb: Callable = Callable(self, "_on_sort_option_selected")
	if not sort_option_button.item_selected.is_connected(selection_cb):
		sort_option_button.item_selected.connect(selection_cb)

func _add_sort_option(label: String, mode: String) -> void:
	var option_index: int = sort_option_button.get_item_count()
	sort_option_button.add_item(label)
	sort_option_button.set_item_metadata(option_index, mode)

func _select_sort_option_by_mode(mode: String) -> void:
	for idx in range(sort_option_button.get_item_count()):
		if str(sort_option_button.get_item_metadata(idx)) == mode:
			sort_option_button.select(idx)
			return
	sort_option_button.select(0)

func _on_sort_option_selected(index: int) -> void:
	var selected_mode: String = str(sort_option_button.get_item_metadata(index))
	if selected_mode == "":
		selected_mode = SORT_DEFAULT
	if _current_sort_mode == selected_mode:
		return

	_current_sort_mode = selected_mode
	_request_units_list_refresh()

func _sort_units_for_display(owned_units_ids: Array) -> Array:
	var sorted_units: Array = []
	for unit_inst in owned_units_ids:
		if unit_inst is Dictionary:
			sorted_units.append(unit_inst)

	if _current_sort_mode == SORT_DEFAULT:
		return sorted_units

	sorted_units.sort_custom(_compare_units_for_sort_mode)
	return sorted_units

func _compare_units_for_sort_mode(a: Dictionary, b: Dictionary) -> bool:
	match _current_sort_mode:
		SORT_NAME_ASC:
			var a_name: String = _get_unit_display_name(a)
			var b_name: String = _get_unit_display_name(b)
			if a_name == b_name:
				return _compare_unit_tie_breaker(a, b)
			return a_name < b_name
		SORT_NAME_DESC:
			var a_name: String = _get_unit_display_name(a)
			var b_name: String = _get_unit_display_name(b)
			if a_name == b_name:
				return _compare_unit_tie_breaker(a, b)
			return a_name > b_name
		SORT_LEVEL_ASC:
			var a_level: int = int(a.get("level", 1))
			var b_level: int = int(b.get("level", 1))
			if a_level == b_level:
				return _compare_unit_tie_breaker(a, b)
			return a_level < b_level
		SORT_LEVEL_DESC:
			var a_level: int = int(a.get("level", 1))
			var b_level: int = int(b.get("level", 1))
			if a_level == b_level:
				return _compare_unit_tie_breaker(a, b)
			return a_level > b_level
		SORT_RARITY_ASC:
			var a_rarity: int = int(a.get("rarity", 1))
			var b_rarity: int = int(b.get("rarity", 1))
			if a_rarity == b_rarity:
				return _compare_unit_tie_breaker(a, b)
			return a_rarity < b_rarity
		SORT_RARITY_DESC:
			var a_rarity: int = int(a.get("rarity", 1))
			var b_rarity: int = int(b.get("rarity", 1))
			if a_rarity == b_rarity:
				return _compare_unit_tie_breaker(a, b)
			return a_rarity > b_rarity
		_:
			return _compare_unit_tie_breaker(a, b)

func _compare_unit_tie_breaker(a: Dictionary, b: Dictionary) -> bool:
	var a_name: String = _get_unit_display_name(a)
	var b_name: String = _get_unit_display_name(b)
	if a_name != b_name:
		return a_name < b_name

	var a_instance_id: String = str(a.get("instance_id", ""))
	var b_instance_id: String = str(b.get("instance_id", ""))
	return a_instance_id < b_instance_id

func _get_unit_display_name(unit_inst: Dictionary) -> String:
	var unit_id: String = str(unit_inst.get("unit_id", ""))
	if unit_id == "":
		return ""

	var unit_data: Dictionary = StaticData.game_data_units.get(unit_id, {})
	return str(unit_data.get("name", "Unknown")).to_lower()

func _should_display_unit(unit_instance_id: String) -> bool:
	if unit_instance_id == "":
		return false
	if mode == "enhance_base_selection" and _selected_units_map.has(unit_instance_id):
		return false
	return not _exclude_instance_id_set.has(unit_instance_id)

func _set_checkbox_state(check_box: CheckBox, state: bool) -> void:
	_suppress_checkbox_signal = true
	check_box.button_pressed = state
	_suppress_checkbox_signal = false

func _is_playable_unit(unit_inst: Dictionary) -> bool:
	var unit_id: String = str(unit_inst.get("unit_id", ""))
	if unit_id == "":
		return false

	var unit_data: Dictionary = StaticData.game_data_units.get(unit_id, {})
	var job_id: int = int(unit_data.get("job_id", 0))
	return job_id != EXP_UNIT_JOB_ID and job_id != TRUST_MATERIAL_JOB_ID

func _is_max_trust_playable_material(unit_inst: Dictionary) -> bool:
	if mode != "enhance_material_selection":
		return false
	if not _is_playable_unit(unit_inst):
		return false

	var trust_value: float = float(unit_inst.get("trust_value", 0.0))
	return trust_value >= ENHANCE_MAX_TRUST_VALUE

func _on_material_checkbox_toggled(checked: bool, unit_inst: Dictionary) -> void:
	if _suppress_checkbox_signal:
		return
	_apply_material_toggle(unit_inst, checked)

func _apply_material_toggle(unit_inst: Dictionary, checked: bool) -> void:
	var instance_id: String = str(unit_inst.get("instance_id", ""))
	if instance_id == "":
		return
	if _is_max_trust_playable_material(unit_inst):
		_selected_units_map.erase(instance_id)
		var check_box: CheckBox = _material_checkboxes.get(instance_id, null) as CheckBox
		if check_box != null:
			_set_checkbox_state(check_box, false)
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
	for entry in UnitService.owned_units_ids:
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
	if not _has_rendered_once:
		return
	if _get_effective_cell_width() == _last_effective_cell_width:
		return
	_request_units_list_refresh()

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

func _on_unit_clicked(unit_inst: Dictionary) -> void:
	if mode == "view":
		UIManager.push("unit_detail_ui", {"unit_inst": unit_inst})
	elif mode == "select":
		unit_selected.emit(unit_inst)
		PartyService.assign_unit_to_party(target_party_index, target_slot_index, unit_inst.instance_id)
		UIManager.pop()
	elif mode == "enhance_base_selection":
		unit_selected.emit(unit_inst)
		UIManager.pop()
		if selection_callback.is_valid():
			selection_callback.call(unit_inst)
	elif mode == "enhance_material_selection":
		if _is_max_trust_playable_material(unit_inst):
			return
		var instance_id: String = str(unit_inst.get("instance_id", ""))
		var check_box: CheckBox = _material_checkboxes.get(instance_id, null) as CheckBox
		if check_box == null:
			return
		var next_state: bool = not check_box.button_pressed
		_set_checkbox_state(check_box, next_state)
		_apply_material_toggle(unit_inst, next_state)
