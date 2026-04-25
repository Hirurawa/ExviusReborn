extends Control

const UNIT_SCENE: PackedScene = preload("res://features/shared/Unit.tscn")

@onready var units_scroll_container: ScrollContainer = $VBoxContainer/ScrollContainer
@onready var units_list_container: GridContainer = $VBoxContainer/ScrollContainer/UnitsListContainer

var mode: String = "view"
var target_party_index: int = 0
var target_slot_index: int = 0

const GRID_COLUMNS: int = 5
const UNIT_CELL_W: int = 128
const UNIT_CELL_H: int = 164
const UNIT_NAME_H: int = 34
const PEDESTAL_BOTTOM_MARGIN: int = 2
const UNIT_SIDE_PADDING: int = 4
const UNIT_FEET_OFFSET_ESTIMATE: float = 5.0
const V_SCROLLBAR_MIN_W: float = 12.0

signal unit_selected(unit_inst: Dictionary)

var _texture_cache: Dictionary = {}

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

func _ready() -> void:
	units_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	units_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_configure_vertical_scrollbar()
	units_list_container.columns = GRID_COLUMNS
	units_scroll_container.resized.connect(_on_scroll_metrics_changed)
	DataManager.units_updated.connect(_on_units_updated)
	_refresh_units_list(DataManager.owned_units_ids)

func _on_units_updated(units: Array) -> void:
	_refresh_units_list(units)

func _refresh_units_list(owned_units_ids: Array) -> void:
	var cell_width: int = _get_effective_cell_width()
	units_list_container.columns = GRID_COLUMNS

	for child in units_list_container.get_children():
		child.queue_free()

	# Back button if in select mode (should be added before early return)
	if mode == "select":
		var back_btn: Button = Button.new()
		back_btn.text = "Back"
		back_btn.pressed.connect(func(): UIManager.pop())
		units_list_container.add_child(back_btn)

	if owned_units_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No units owned."
		units_list_container.add_child(empty_label)
		return

	for unit_inst in owned_units_ids:
		if not unit_inst is Dictionary:
			continue

		var unit_id: String = unit_inst.get("unit_id", "")
		var unit_data: Dictionary = DataManager.game_data_units.get(unit_id, {})
		
		# Keep five columns and shrink cell width only when viewport is tight.
		var container: Control = Control.new()
		container.custom_minimum_size = Vector2(cell_width, UNIT_CELL_H)
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		container.clip_contents = true

		# Load textures first to determine pixel-perfect sizing.
		var sprite_texture: Texture2D = null
		var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
		if ResourceLoader.exists(img_path):
			sprite_texture = _get_dynamic_texture(img_path)

		var pedestal_texture: Texture2D = _get_pedestal_texture(unit_inst.get("rarity", 1))

		var visual_area_h: int = UNIT_CELL_H
		var center_x: float = float(cell_width) * 0.5
		var available_w: float = float(cell_width - (UNIT_SIDE_PADDING * 2))

		var visual_container: Control = Control.new()
		visual_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visual_container.clip_contents = true

		if sprite_texture and pedestal_texture:
			var sprite_source_size: Vector2 = sprite_texture.get_size()
			var pedestal_source_size: Vector2 = pedestal_texture.get_size()
			var width_reference: float = maxf(sprite_source_size.x, pedestal_source_size.x)
			var height_reference: float = maxf(pedestal_source_size.y, sprite_source_size.y + UNIT_FEET_OFFSET_ESTIMATE)
			var width_limit_scale: float = available_w / maxf(1.0, width_reference)
			var height_limit_scale: float = float(visual_area_h - PEDESTAL_BOTTOM_MARGIN) / maxf(1.0, height_reference)
			var final_scale: float = maxf(0.05, minf(width_limit_scale, height_limit_scale))

			var unit_visual: Control = UNIT_SCENE.instantiate() as Control
			if unit_visual:
				unit_visual.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
				unit_visual.scale = Vector2(final_scale, final_scale)
				visual_container.add_child(unit_visual)
				var pedestal_half_h: float = (pedestal_source_size.y * final_scale) * 0.5
				unit_visual.position = Vector2(center_x, float(visual_area_h - PEDESTAL_BOTTOM_MARGIN) - pedestal_half_h)
				unit_visual.call_deferred("setup", sprite_texture, pedestal_texture)

		container.add_child(visual_container)

		var click_btn: Button = Button.new()
		click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		click_btn.pressed.connect(_on_unit_clicked.bind(unit_inst))
		click_btn.z_index = 20
		container.add_child(click_btn)

		# Name label overlaid at bottom
		var name_label: Label = Label.new()
		name_label.text = unit_data.get("name", "Unknown")
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.anchor_left = 0.0
		name_label.anchor_right = 1.0
		name_label.anchor_top = 1.0
		name_label.anchor_bottom = 1.0
		name_label.offset_left = 2
		name_label.offset_right = -2
		name_label.offset_top = -UNIT_NAME_H
		name_label.offset_bottom = -2
		name_label.z_index = 10
		container.add_child(name_label)

		units_list_container.add_child(container)

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
