extends Control

@onready var base_unit_id_label: Label = $EnhanceFlowRoot/BaseUnitIdLabel
@onready var base_unit_sprite: TextureRect = $EnhanceFlowRoot/BaseUnitDisplay/BaseUnitSprite
@onready var materials_container: HBoxContainer = $EnhanceFlowRoot/MaterialPedestalsContainer
@onready var cancel_button: Button = $EnhanceFlowRoot/UnitNamebgChara/UnitMinibutton1
@onready var clear_button: Button = $unit_mix_ui_bg/unit_mix_button_clear
@onready var confirm_button: Button = $unit_mix_ui_bg/unit_mix_button_union

@onready var UnitLevel: Label = $UnitLevel/UnitLevel

@onready var HP: Label = $unit_statusbg/unit_status_label_hp/unit_status_ext_hp_now_number
@onready var MP: Label = $unit_statusbg/unit_status_label_mp/unit_status_ext_mp_now_number
@onready var ATK: Label = $unit_statusbg/unit_status_label_attack/unit_status_ext_attack_now_number
@onready var DEF:Label = $unit_statusbg/unit_status_label_defense/unit_status_ext_defense_now_number
@onready var MAG: Label = $unit_statusbg/unit_status_label_magic/unit_status_ext_magic_now_number
@onready var SPR: Label = $unit_statusbg/unit_status_label_mnd/unit_status_ext_mnd_now_number

@onready var LBName: Label = $UnitLbframe/LBName
@onready var TMName: Label = $TM/unit_mix_bonds_name

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
	_display_unit_stats(base_unit_inst)

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
	print("CONFIRM")
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

func _display_unit_stats(unit_inst: Dictionary) -> void:
	if unit_inst.is_empty():
		return
	
	UnitLevel.text = str(int(unit_inst.level))
	var currentRarity = int(unit_inst.current_rarity)
	var maxLevel = StatCalculator.RARITY_MAX_LEVELS.get(int(currentRarity), 15)
	UnitLevel.text += " / " + str(maxLevel)
	var xp = int(unit_inst.xp)
	var currentXp = int(unit_inst.xp)
	var xpForNextLevel = int(unit_inst.next_xp)
	var lb_id = str(int(unit_inst.get("limitburst_id", "")))
	if lb_id != "" and DataManager.game_data_limitbursts.has(lb_id):
		LBName.text = DataManager.game_data_limitbursts[lb_id].get("name", "Unknown Limit Burst")
	
	var tmr_data = unit_inst.get("TMR")
	if tmr_data != null and typeof(tmr_data) == TYPE_ARRAY and tmr_data.size() >= 2:
		var tmr_type = tmr_data[0]
		var tmr_id = str(int(tmr_data[1]))
		var tmr_name = "Unknown Reward"

		if tmr_type == "EQUIP":
			if DataManager.game_data_equipment.has(tmr_id):
				var eq_data = DataManager.game_data_equipment[tmr_id]
				tmr_name = eq_data.get("name", tmr_name)
		elif tmr_type == "MATERIA":
			if DataManager.game_data_materia.has(tmr_id):
				var mat_data = DataManager.game_data_materia[tmr_id]
				tmr_name = mat_data.get("name", tmr_name)

		TMName.text = tmr_name
	else:
		TMName.text = "None"
	
	
	HP.text = str(unit_inst.final_stats["stats"].get("HP"))
	MP.text = str(unit_inst.final_stats["stats"].get("MP"))
	ATK.text = str(unit_inst.final_stats["stats"].get("ATK"))
	DEF.text = str(unit_inst.final_stats["stats"].get("DEF"))
	MAG.text = str(unit_inst.final_stats["stats"].get("MAG"))
	SPR.text = str(unit_inst.final_stats["stats"].get("SPR"))
