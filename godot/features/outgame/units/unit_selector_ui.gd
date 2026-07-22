extends Control

const UNIT_SCENE: PackedScene = preload("res://features/shared/Unit.tscn")

@onready var vbox_container: VBoxContainer = $VBoxContainer
@onready var title_label: Label = $VBoxContainer/UnitNamebgChara/Title
@onready var units_scroll_container: ScrollContainer = $VBoxContainer/ScrollContainer
@onready var units_list_container: GridContainer = $VBoxContainer/ScrollContainer/UnitsListContainer
@onready var sort_option_button: OptionButton = $VBoxContainer/UnitNamebgChara/SortOptionButton
@onready var sell_button: Button = $VBoxContainer/UnitNamebgChara/SellButton
@onready var search_bar: Control = $VBoxContainer/SearchBar
@onready var search_input: LineEdit = $VBoxContainer/SearchBar/SearchInput
@onready var search_clear_button: Button = $VBoxContainer/SearchBar/ClearButton

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
const SORT_NEWEST: String = "newest"
const SORT_OLDEST: String = "oldest"
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
static var _persisted_sort_mode: String = ""
static var _persisted_sort_loaded: bool = false

const SORT_CONFIG_PATH: String = "user://unit_selector_sort.cfg"
const SORT_CONFIG_SECTION: String = "unit_selector"
const SORT_CONFIG_KEY: String = "sort_mode"

const SEARCH_BAR_EXPANDED_H: float = 56.0
const PULL_REVEAL_THRESHOLD_PX: float = 40.0
const PULL_COLLAPSE_THRESHOLD_PX: float = 40.0
const REVEAL_TWEEN_TIME: float = 0.18
const SEARCH_DEBOUNCE_SEC: float = 0.15

var _exclude_instance_id_set: Dictionary = {}
var _selected_units_map: Dictionary = {}
var _material_checkboxes: Dictionary = {}
var _suppress_checkbox_signal: bool = false
var _current_sort_mode: String = SORT_DEFAULT
var _sell_mode_active: bool = false
var _pending_sell_ids: Array = []
var _sell_confirm_dialog: ConfirmationDialog = null
var _has_received_init_params: bool = false
var _has_rendered_once: bool = false
var _refresh_scheduled: bool = false
var _last_effective_cell_width: int = -1
var _search_query: String = ""
var _search_bar_expanded: bool = false
var _pull_accumulator: float = 0.0
var _search_debounce_timer: Timer = null
var _search_reveal_tween: Tween = null

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
	_setup_search_bar()
	
	back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	back_button.pressed.connect(_on_back_pressed)

	clear_button.mouse_filter = Control.MOUSE_FILTER_STOP
	clear_button.pressed.connect(_on_clear_material_selection)

	confirm_button.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_button.pressed.connect(_on_confirm_material_selection)

	if sell_button != null:
		sell_button.mouse_filter = Control.MOUSE_FILTER_STOP
		sell_button.pressed.connect(_on_sell_toggle_pressed)
	
	_update_mode_ui()
	_configure_vertical_scrollbar()
	units_list_container.columns = GRID_COLUMNS
	units_scroll_container.resized.connect(_on_scroll_metrics_changed)
	units_scroll_container.gui_input.connect(_on_scroll_gui_input)
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
			title_label.text = "Select Base to Enhance"
		"awaken_base_selection":
			title_label.text = "Select Base to Awaken"
		"enhance_material_selection":
			title_label.text = "Select Material Units"
		_:
			title_label.text = "View Units"

	if action_row == null:
		return

	# Always show action row in selector modes
	var selector_mode: bool = mode == "select" or mode == "enhance_material_selection" or _sell_mode_active
	action_row.visible = selector_mode

	if _sell_mode_active:
		title_label.text = "Select Units to Sell"

	if sell_button != null:
		sell_button.visible = mode == "view"

func _on_clear_material_selection() -> void:
	_selected_units_map.clear()
	for key in _material_checkboxes.keys():
		var check_box: CheckBox = _material_checkboxes.get(key, null) as CheckBox
		if check_box != null:
			_set_checkbox_state(check_box, false)

func _on_units_updated(_units: Array) -> void:
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
		if _search_query != "":
			empty_label.text = "No units match '%s'." % _search_query
		else:
			empty_label.text = "No units owned."
		units_list_container.add_child(empty_label)
		return

	for unit_inst in sorted_units:
		if not unit_inst is Dictionary:
			continue

		var unit_instance_id: String = str(unit_inst.get("instance_id", ""))
		if not _should_display_unit(unit_instance_id):
			continue

		var is_disabled_max_trust_material: bool = _is_max_trust_playable_material(unit_inst)
		var is_disabled_max_rarity_awaken: bool = mode == "awaken_base_selection" and _is_at_max_rarity(unit_inst)
		var is_disabled_sell_blocked: bool = _is_unit_sell_blocked(unit_inst)
		if is_disabled_max_trust_material or is_disabled_sell_blocked:
			_selected_units_map.erase(unit_instance_id)
		
		# Keep five columns and shrink cell width only when viewport is tight.
		var container: Control = Control.new()
		container.custom_minimum_size = Vector2(cell_width, UNIT_CELL_H)
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_FILL

		var visual_container: Control = Control.new()
		visual_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var unit_visual: Control = UNIT_SCENE.instantiate() as Control
		if unit_visual:
			unit_visual.unit_data_to_load = unit_inst
			unit_visual.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
			visual_container.add_child(unit_visual)
		
		container.add_child(visual_container)

		var click_btn: Button = Button.new()
		click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.pressed.connect(_on_unit_clicked.bind(unit_inst))
		click_btn.z_index = 18
		if is_disabled_max_rarity_awaken:
			click_btn.disabled = true
			click_btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
			click_btn.tooltip_text = "Already at max rarity"
		elif is_disabled_sell_blocked:
			click_btn.disabled = true
			click_btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
			click_btn.tooltip_text = "Locked or in-party units cannot be sold"
		container.add_child(click_btn)
		if is_disabled_max_trust_material or is_disabled_max_rarity_awaken or is_disabled_sell_blocked:
			container.modulate = Color(1.0, 1.0, 1.0, 0.45)

		if is_disabled_max_rarity_awaken:
			var max_badge: Label = Label.new()
			max_badge.text = "MAX"
			max_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			max_badge.position = Vector2(-48, 6)
			max_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			max_badge.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
			max_badge.add_theme_constant_override("outline_size", 2)
			max_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			max_badge.z_index = 30
			container.add_child(max_badge)

		if _is_multi_select_active():
			var check_box: CheckBox = CheckBox.new()
			check_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			check_box.position = Vector2(4, 4)
			check_box.z_index = 25
			check_box.mouse_filter = Control.MOUSE_FILTER_STOP
			var checked: bool = _selected_units_map.has(unit_instance_id)
			_set_checkbox_state(check_box, checked)
			check_box.disabled = is_disabled_max_trust_material or is_disabled_sell_blocked
			if is_disabled_max_trust_material:
				check_box.tooltip_text = "Cannot use a playable unit at 100% trust as enhancement material"
			elif is_disabled_sell_blocked:
				check_box.tooltip_text = "Locked or in-party units cannot be sold"
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

	_current_sort_mode = _load_persisted_sort_mode()
	sort_option_button.clear()
	_add_sort_option("Sort: Default", SORT_DEFAULT)
	_add_sort_option("Newest First", SORT_NEWEST)
	_add_sort_option("Oldest First", SORT_OLDEST)
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

func _add_sort_option(label: String, sort_mode: String) -> void:
	var option_index: int = sort_option_button.get_item_count()
	sort_option_button.add_item(label)
	sort_option_button.set_item_metadata(option_index, sort_mode)

func _select_sort_option_by_mode(sort_mode: String) -> void:
	for idx in range(sort_option_button.get_item_count()):
		if str(sort_option_button.get_item_metadata(idx)) == sort_mode:
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
	_persist_sort_mode(selected_mode)
	_request_units_list_refresh()

static func _load_persisted_sort_mode() -> String:
	if _persisted_sort_loaded:
		return _persisted_sort_mode
	_persisted_sort_loaded = true
	var config: ConfigFile = ConfigFile.new()
	if config.load(SORT_CONFIG_PATH) == OK:
		_persisted_sort_mode = str(config.get_value(SORT_CONFIG_SECTION, SORT_CONFIG_KEY, SORT_DEFAULT))
	else:
		_persisted_sort_mode = SORT_DEFAULT
	return _persisted_sort_mode

static func _persist_sort_mode(sort_mode: String) -> void:
	_persisted_sort_mode = sort_mode
	_persisted_sort_loaded = true
	var config: ConfigFile = ConfigFile.new()
	config.load(SORT_CONFIG_PATH)
	config.set_value(SORT_CONFIG_SECTION, SORT_CONFIG_KEY, sort_mode)
	config.save(SORT_CONFIG_PATH)

func _setup_search_bar() -> void:
	if search_bar == null:
		return

	search_bar.custom_minimum_size = Vector2(search_bar.custom_minimum_size.x, 0.0)
	search_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_search_bar_expanded = false
	_pull_accumulator = 0.0
	_search_query = ""

	if search_input != null:
		search_input.text = ""
		search_input.placeholder_text = "Filter by name"
		if not search_input.text_changed.is_connected(_on_search_text_changed):
			search_input.text_changed.connect(_on_search_text_changed)
		if not search_input.text_submitted.is_connected(_on_search_text_submitted):
			search_input.text_submitted.connect(_on_search_text_submitted)

	if search_clear_button != null:
		if not search_clear_button.pressed.is_connected(_on_search_clear_pressed):
			search_clear_button.pressed.connect(_on_search_clear_pressed)

	if _search_debounce_timer == null:
		_search_debounce_timer = Timer.new()
		_search_debounce_timer.one_shot = true
		_search_debounce_timer.wait_time = SEARCH_DEBOUNCE_SEC
		_search_debounce_timer.timeout.connect(_apply_search_query)
		add_child(_search_debounce_timer)

func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_pull_accumulator = 0.0
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not st.pressed:
			_pull_accumulator = 0.0
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_process_pull_delta(mm.relative.y)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_process_pull_delta(sd.relative.y)

func _process_pull_delta(delta_y: float) -> void:
	if units_scroll_container == null:
		return
	if units_scroll_container.scroll_vertical > 0:
		_pull_accumulator = 0.0
		return

	if not _search_bar_expanded:
		if delta_y > 0.0:
			_pull_accumulator += delta_y
			if _pull_accumulator >= PULL_REVEAL_THRESHOLD_PX:
				_pull_accumulator = 0.0
				_expand_search_bar()
		else:
			_pull_accumulator = 0.0
		return

	if _search_query != "":
		_pull_accumulator = 0.0
		return

	if delta_y < 0.0:
		_pull_accumulator += -delta_y
		if _pull_accumulator >= PULL_COLLAPSE_THRESHOLD_PX:
			_pull_accumulator = 0.0
			_collapse_search_bar()
	else:
		_pull_accumulator = 0.0

func _expand_search_bar() -> void:
	if _search_bar_expanded or search_bar == null:
		return
	_search_bar_expanded = true
	_tween_search_bar_height(SEARCH_BAR_EXPANDED_H, Tween.EASE_OUT)
	if search_input != null:
		search_input.grab_focus()

func _collapse_search_bar() -> void:
	if not _search_bar_expanded or search_bar == null:
		return
	_search_bar_expanded = false
	if search_input != null:
		search_input.release_focus()
	_tween_search_bar_height(0.0, Tween.EASE_IN)

func _tween_search_bar_height(target_h: float, ease_mode: int) -> void:
	if _search_reveal_tween != null and _search_reveal_tween.is_running():
		_search_reveal_tween.kill()
	_search_reveal_tween = create_tween()
	_search_reveal_tween.tween_property(
		search_bar,
		"custom_minimum_size:y",
		target_h,
		REVEAL_TWEEN_TIME
	).set_trans(Tween.TRANS_SINE).set_ease(ease_mode)

func _on_search_text_changed(_new_text: String) -> void:
	if _search_debounce_timer != null:
		_search_debounce_timer.start()

func _on_search_text_submitted(_new_text: String) -> void:
	if _search_debounce_timer != null:
		_search_debounce_timer.stop()
	_apply_search_query()

func _on_search_clear_pressed() -> void:
	if search_input == null:
		return
	if search_input.text == "" and _search_query == "":
		return
	search_input.text = ""
	if _search_debounce_timer != null:
		_search_debounce_timer.stop()
	if _search_query != "":
		_search_query = ""
		_request_units_list_refresh()

func _apply_search_query() -> void:
	if search_input == null:
		return
	var normalized: String = search_input.text.strip_edges().to_lower()
	if normalized == _search_query:
		return
	_search_query = normalized
	_request_units_list_refresh()

func _unit_matches_search_query(unit_inst: Dictionary) -> bool:
	if _search_query == "":
		return true
	var display_name: String = unit_inst.get("unitName").to_lower()
	return display_name.find(_search_query) != -1

func _sort_units_for_display(owned_units_ids: Array) -> Array:
	var sorted_units: Array = []
	for unit_inst in owned_units_ids:
		if not (unit_inst is Dictionary):
			continue
		if _search_query != "" and not _unit_matches_search_query(unit_inst):
			continue
		sorted_units.append(unit_inst)

	# owned_units_ids preserves acquisition order (new units are appended), so
	# the filtered array is already oldest-first. Newest-first simply reverses it.
	match _current_sort_mode:
		SORT_DEFAULT, SORT_OLDEST:
			pass
		SORT_NEWEST:
			sorted_units.reverse()
		_:
			sorted_units.sort_custom(_compare_units_for_sort_mode)

	if mode == "awaken_base_selection":
		var awakenable: Array = []
		var maxed: Array = []
		for unit_inst in sorted_units:
			if _is_at_max_rarity(unit_inst):
				maxed.append(unit_inst)
			else:
				awakenable.append(unit_inst)
		awakenable.append_array(maxed)
		return awakenable

	return sorted_units

func _compare_units_for_sort_mode(a: Dictionary, b: Dictionary) -> bool:
	match _current_sort_mode:
		SORT_NAME_ASC:
			var a_name: String = a.get("unitName").to_lower()
			var b_name: String = b.get("unitName").to_lower()
			if a_name == b_name:
				return _compare_unit_tie_breaker(a, b)
			return a_name < b_name
		SORT_NAME_DESC:
			var a_name: String = a.get("unitName").to_lower()
			var b_name: String = b.get("unitName").to_lower()
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
			var a_rarity: int = int(a.get("current_rarity", a.get("rarity", 1)))
			var b_rarity: int = int(b.get("current_rarity", b.get("rarity", 1)))
			if a_rarity == b_rarity:
				return _compare_unit_tie_breaker(a, b)
			return a_rarity < b_rarity
		SORT_RARITY_DESC:
			var a_rarity: int = int(a.get("current_rarity", a.get("rarity", 1)))
			var b_rarity: int = int(b.get("current_rarity", b.get("rarity", 1)))
			if a_rarity == b_rarity:
				return _compare_unit_tie_breaker(a, b)
			return a_rarity > b_rarity
		_:
			return _compare_unit_tie_breaker(a, b)

func _compare_unit_tie_breaker(a: Dictionary, b: Dictionary) -> bool:
	var a_name: String = a.get("unitName").to_lower()
	var b_name: String = b.get("unitName").to_lower()
	if a_name != b_name:
		return a_name < b_name

	var a_instance_id: String = str(a.get("instance_id", ""))
	var b_instance_id: String = str(b.get("instance_id", ""))
	return a_instance_id < b_instance_id

func _should_display_unit(unit_instance_id: String) -> bool:
	if unit_instance_id == "":
		return false
	if mode == "enhance_base_selection" and _selected_units_map.has(unit_instance_id):
		return false
	return not _exclude_instance_id_set.has(unit_instance_id)

func _is_at_max_rarity(unit_inst: Dictionary) -> bool:
	var current_rarity: int = int(unit_inst.get("current_rarity"))
	return current_rarity >= GameDatabase.get_unit_max_rarity(unit_inst.get("unitSeries"))

func _set_checkbox_state(check_box: CheckBox, state: bool) -> void:
	_suppress_checkbox_signal = true
	check_box.button_pressed = state
	_suppress_checkbox_signal = false

func _is_playable_unit(unit_inst: Dictionary) -> bool:
	var job_id: int = int(unit_inst.get("jobId", 0))
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
	if _is_max_trust_playable_material(unit_inst) or _is_unit_sell_blocked(unit_inst):
		_selected_units_map.erase(instance_id)
		var check_box: CheckBox = _material_checkboxes.get(instance_id, null) as CheckBox
		if check_box != null:
			_set_checkbox_state(check_box, false)
		return

	if checked:
		if _selected_units_map.has(instance_id):
			return
		if not _sell_mode_active and _selected_units_map.size() >= MAX_MATERIAL_SELECTION:
			var check_box: CheckBox = _material_checkboxes.get(instance_id, null) as CheckBox
			if check_box != null:
				_set_checkbox_state(check_box, false)
			return
		_selected_units_map[instance_id] = unit_inst
		return

	_selected_units_map.erase(instance_id)

func _on_confirm_material_selection() -> void:
	if _sell_mode_active:
		_on_confirm_sell()
		return
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

func _is_multi_select_active() -> bool:
	return mode == "enhance_material_selection" or _sell_mode_active

func _is_unit_sell_blocked(unit_inst: Dictionary) -> bool:
	if not _sell_mode_active:
		return false
	if bool(unit_inst.get("is_locked", false)):
		return true
	var instance_id: String = str(unit_inst.get("instance_id", ""))
	if instance_id == "":
		return true
	return PartyService.is_unit_assigned_to_any_party(instance_id)

func _on_sell_toggle_pressed() -> void:
	if _sell_mode_active:
		_exit_sell_mode()
	else:
		_enter_sell_mode()

func _enter_sell_mode() -> void:
	if mode != "view":
		return
	_sell_mode_active = true
	_selected_units_map.clear()
	if sell_button != null:
		sell_button.text = "Cancel"
	_update_mode_ui()
	_request_units_list_refresh()

func _exit_sell_mode() -> void:
	_sell_mode_active = false
	_selected_units_map.clear()
	_pending_sell_ids.clear()
	if sell_button != null:
		sell_button.text = "Sell"
	if title_label != null:
		title_label.text = "View Units"
	_update_mode_ui()
	_request_units_list_refresh()

func _on_confirm_sell() -> void:
	var ordered_selection: Array = []
	for entry in UnitService.owned_units_ids:
		if not (entry is Dictionary):
			continue
		var instance_id: String = str(entry.get("instance_id", ""))
		if instance_id == "":
			continue
		if _selected_units_map.has(instance_id):
			ordered_selection.append(instance_id)

	if ordered_selection.is_empty():
		return

	_pending_sell_ids = ordered_selection
	var total_gil: int = ordered_selection.size() * UnitService.SELL_GIL_PER_UNIT
	var dialog: ConfirmationDialog = _ensure_sell_confirm_dialog()
	dialog.dialog_text = "Sell %d unit(s) for %d gil?" % [ordered_selection.size(), total_gil]
	dialog.popup_centered()

func _ensure_sell_confirm_dialog() -> ConfirmationDialog:
	if _sell_confirm_dialog == null:
		_sell_confirm_dialog = ConfirmationDialog.new()
		_sell_confirm_dialog.title = "Sell Units"
		_sell_confirm_dialog.confirmed.connect(_on_sell_confirmed)
		add_child(_sell_confirm_dialog)
	return _sell_confirm_dialog

func _on_sell_confirmed() -> void:
	if _pending_sell_ids.is_empty():
		return
	var ids: Array = _pending_sell_ids.duplicate()
	_pending_sell_ids.clear()
	var result: Dictionary = UnitService.sell_units(ids)
	if not bool(result.get("success", false)):
		return
	_exit_sell_mode()

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
	if _sell_mode_active:
		if _is_unit_sell_blocked(unit_inst):
			return
		var sell_instance_id: String = str(unit_inst.get("instance_id", ""))
		var sell_check_box: CheckBox = _material_checkboxes.get(sell_instance_id, null) as CheckBox
		if sell_check_box == null:
			return
		var sell_next_state: bool = not sell_check_box.button_pressed
		_set_checkbox_state(sell_check_box, sell_next_state)
		_apply_material_toggle(unit_inst, sell_next_state)
		return
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
	elif mode == "awaken_base_selection":
		if _is_at_max_rarity(unit_inst):
			return
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
