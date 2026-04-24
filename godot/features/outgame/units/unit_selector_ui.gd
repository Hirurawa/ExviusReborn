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

		# Layered Control so the pedestal can be overlaid at the bottom of the sprite
		const SPRITE_W: int = 80
		const SPRITE_H: int = 100
		const PEDESTAL_H: int = 28

		var sprite_container: Control = Control.new()
		sprite_container.custom_minimum_size = Vector2(SPRITE_W, SPRITE_H)
		sprite_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Prevent the VBoxContainer from stretching this vertically beyond its minimum
		sprite_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var tex_btn: TextureButton = TextureButton.new()
		var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
		if ResourceLoader.exists(img_path):
			var tex: Texture2D = _get_dynamic_texture(img_path)
			if tex:
				tex_btn.texture_normal = tex

		tex_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex_btn.ignore_texture_size = true
		tex_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tex_btn.pressed.connect(_on_unit_clicked.bind(unit_inst))
		sprite_container.add_child(tex_btn)

		# Pedestal affixed at the bottom using explicit position/size to avoid anchor timing issues
		var charastand_path: String = "res://assets/ui/unit/unit_charastand_rare%s_small.tres" % unit_inst.get("rarity", 1)
		if ResourceLoader.exists(charastand_path):
			var pedestal_rect: TextureRect = TextureRect.new()
			var tex_pedestal: Texture2D = _get_dynamic_texture(charastand_path) as Texture2D
			if tex_pedestal:
				pedestal_rect.texture = tex_pedestal
			pedestal_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pedestal_rect.position = Vector2(0, SPRITE_H - PEDESTAL_H)
			pedestal_rect.size = Vector2(SPRITE_W, PEDESTAL_H)
			sprite_container.add_child(pedestal_rect)

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
