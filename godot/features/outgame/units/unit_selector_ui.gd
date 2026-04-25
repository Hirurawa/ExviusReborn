extends Control

@onready var units_list_container: GridContainer = $VBoxContainer/ScrollContainer/UnitsListContainer

var mode: String = "view"
var target_party_index: int = 0
var target_slot_index: int = 0

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
	DataManager.units_updated.connect(_on_units_updated)
	_refresh_units_list(DataManager.owned_units_ids)

func _on_units_updated(units: Array) -> void:
	_refresh_units_list(units)

func _refresh_units_list(owned_units_ids: Array) -> void:
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
		
		var container: VBoxContainer = VBoxContainer.new()
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.alignment = BoxContainer.ALIGNMENT_CENTER

		# Layered tile for deterministic sprite + pedestal composition.
		const TILE_W: int = 120
		const TILE_H: int = 120
		const PEDESTAL_H: int = 52

		var sprite_container: Control = Control.new()
		sprite_container.custom_minimum_size = Vector2(TILE_W, TILE_H)
		sprite_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sprite_container.clip_contents = true
		# Prevent the VBoxContainer from stretching this vertically beyond its minimum.
		sprite_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var sprite_rect: TextureRect = TextureRect.new()
		sprite_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sprite_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
		if ResourceLoader.exists(img_path):
			var tex: Texture2D = _get_dynamic_texture(img_path)
			if tex:
				sprite_rect.texture = tex

		# Draw pedestal behind the sprite and clamp everything to tile bounds.
		var pedestal_texture: Texture2D = _get_pedestal_texture(unit_inst.get("rarity", 1))
		if pedestal_texture:
			var pedestal_rect: TextureRect = TextureRect.new()
			pedestal_rect.texture = pedestal_texture
			pedestal_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pedestal_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pedestal_rect.position = Vector2(0, TILE_H - PEDESTAL_H)
			pedestal_rect.size = Vector2(TILE_W, PEDESTAL_H)
			pedestal_rect.z_index = 0
			sprite_container.add_child(pedestal_rect)

		sprite_rect.z_index = 1
		sprite_container.add_child(sprite_rect)

		var click_btn: Button = Button.new()
		click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		click_btn.pressed.connect(_on_unit_clicked.bind(unit_inst))
		click_btn.z_index = 2
		sprite_container.add_child(click_btn)

		container.add_child(sprite_container)

		var name_label: Label = Label.new()
		name_label.text = unit_data.get("name", "Unknown")
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 12)
		container.add_child(name_label)

		units_list_container.add_child(container)

func _on_unit_clicked(unit_inst: Dictionary) -> void:
	if mode == "view":
		UIManager.push("unit_detail_ui", {"unit_inst": unit_inst})
	elif mode == "select":
		unit_selected.emit(unit_inst)
		DataManager.assign_unit_to_party(target_party_index, target_slot_index, unit_inst.instance_id)
		UIManager.pop()
