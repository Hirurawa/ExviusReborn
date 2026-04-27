extends Control

@onready var base_unit_id_label: Label = $EnhanceFlowRoot/BaseUnitIdLabel
@onready var base_unit_sprite: TextureRect = $EnhanceFlowRoot/BaseUnitDisplay/BaseUnitSprite
@onready var materials_container: HBoxContainer = $EnhanceFlowRoot/MaterialPedestalsContainer
@onready var cancel_button: Button = $EnhanceFlowRoot/EnhanceActionBar/CancelButton
@onready var clear_button: Button = $EnhanceFlowRoot/EnhanceActionBar/ClearButton
@onready var confirm_button: Button = $EnhanceFlowRoot/EnhanceActionBar/ConfirmButton

var base_unit_instance_id: String = ""
var base_unit_inst: Dictionary = {}
var material_units_array: Array = []

var _texture_cache: Dictionary = {}
var _pedestal_slots: Array[Control] = []

func init_scene(params: Dictionary) -> void:
	if params.has("base_unit_instance_id"):
		base_unit_instance_id = str(params.get("base_unit_instance_id", ""))
	if params.has("base_unit_inst") and params.get("base_unit_inst") is Dictionary:
		base_unit_inst = params.get("base_unit_inst", {}).duplicate(true)
	if params.has("material_units_array") and params.get("material_units_array") is Array:
		material_units_array = params.get("material_units_array", []).duplicate(true)
	
	# Defer UI refresh until after init_scene is complete
	call_deferred("_complete_initialization")

func _ready() -> void:
	_collect_pedestal_slots()
	_connect_buttons()

func _complete_initialization() -> void:
	_refresh_base_unit_ui()
	_redraw_material_slots()

func _collect_pedestal_slots() -> void:
	_pedestal_slots.clear()
	for child in materials_container.get_children():
		if child is Control and str(child.name).begins_with("PedestalSlot"):
			_pedestal_slots.append(child)

func _connect_buttons() -> void:
	cancel_button.pressed.connect(_on_cancel_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)

	for slot in _pedestal_slots:
		var hit_button: Button = slot.get_node_or_null("HitButton") as Button
		if hit_button != null:
			hit_button.pressed.connect(_on_any_pedestal_pressed)

func _refresh_base_unit_ui() -> void:
	base_unit_id_label.text = "Base Instance ID: %s" % base_unit_instance_id
	base_unit_sprite.texture = _get_unit_texture(base_unit_inst)

func _redraw_material_slots() -> void:
	for slot in _pedestal_slots:
		var sprite: TextureRect = slot.get_node_or_null("MaterialSprite") as TextureRect
		if sprite == null:
			continue
		sprite.texture = null

	var max_slots: int = mini(_pedestal_slots.size(), 5)
	for i in range(mini(material_units_array.size(), max_slots)):
		var slot: Control = _pedestal_slots[i]
		var sprite: TextureRect = slot.get_node_or_null("MaterialSprite") as TextureRect
		if sprite == null:
			continue
		sprite.texture = _get_unit_texture(material_units_array[i])

func _on_any_pedestal_pressed() -> void:
	if base_unit_instance_id == "":
		return

	var filtered_preselected: Array = []
	for entry in material_units_array:
		if not (entry is Dictionary):
			continue
		var instance_id: String = str(entry.get("instance_id", ""))
		if instance_id == "" or instance_id == base_unit_instance_id:
			continue
		filtered_preselected.append(entry)

	UIManager.push("unit_selector_ui", {
		"mode": "enhance_material_selection",
		"exclude_list": [base_unit_instance_id],
		"pre_selected_units": filtered_preselected,
		"selection_callback": Callable(self, "_on_material_units_selected")
	})

func _on_material_units_selected(selected_units: Array) -> void:
	material_units_array.clear()
	for entry in selected_units:
		if not (entry is Dictionary):
			continue
		var instance_id: String = str(entry.get("instance_id", ""))
		if instance_id == "" or instance_id == base_unit_instance_id:
			continue
		material_units_array.append(entry)
		if material_units_array.size() >= 5:
			break

	_redraw_material_slots()

func _on_clear_pressed() -> void:
	material_units_array.clear()
	_redraw_material_slots()

func _on_confirm_pressed() -> void:
	# UI state only for now. Backend enhancement processing will be wired later.
	pass

func _on_cancel_pressed() -> void:
	UIManager.pop()

func _get_unit_texture(unit_inst: Dictionary) -> Texture2D:
	if unit_inst.is_empty():
		return null

	var unit_id: String = str(unit_inst.get("unit_id", ""))
	if unit_id == "":
		return null

	var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
	if not ResourceLoader.exists(img_path):
		return null

	if _texture_cache.has(img_path):
		return _texture_cache[img_path]

	var tex: Texture2D = ResourceLoader.load(img_path) as Texture2D
	_texture_cache[img_path] = tex
	return tex
