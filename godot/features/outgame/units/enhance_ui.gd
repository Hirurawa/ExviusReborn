extends Control

const UNIT_SCENE: PackedScene = preload("res://features/shared/Unit.tscn")

@onready var base_unit_id_label: Label = $EnhanceFlowRoot/BaseUnitIdLabel
@onready var base_unit_sprite: Control = $EnhanceFlowRoot/BaseUnitDisplay
@onready var materials_container: HBoxContainer = $EnhanceFlowRoot/MaterialPedestalsContainer
@onready var cancel_button: Button = $EnhanceFlowRoot/UnitNamebgChara/UnitMinibutton1
@onready var clear_button: Button = $unit_mix_ui_bg/unit_mix_button_clear
@onready var confirm_button: Button = $unit_mix_ui_bg/unit_mix_button_union
@onready var classup_button: TextureButton = $unit_mix_ui_bg/unit_mix_button_classup
@onready var get_exp_number_label: Label = $unit_mix_ui_sell_info/unit_mix_get_exp_label/unit_mix_get_exp_number
@onready var need_gil_number_label: Label = $unit_mix_ui_sell_info/unit_mix_need_money_label/unit_mix_need_money_number

@onready var UnitLevel: Label = $UnitLevel/UnitLevel

@onready var HP: Label = $unit_statusbg/unit_status_label_hp/unit_status_ext_hp_now_number
@onready var MP: Label = $unit_statusbg/unit_status_label_mp/unit_status_ext_mp_now_number
@onready var ATK: Label = $unit_statusbg/unit_status_label_attack/unit_status_ext_attack_now_number
@onready var DEF:Label = $unit_statusbg/unit_status_label_defense/unit_status_ext_defense_now_number
@onready var MAG: Label = $unit_statusbg/unit_status_label_magic/unit_status_ext_magic_now_number
@onready var SPR: Label = $unit_statusbg/unit_status_label_mnd/unit_status_ext_mnd_now_number

@onready var LBName: Label = $UnitLbframe/LBName
@onready var TMName: Label = $TM/unit_mix_bonds_name
@onready var TMValue: Label = $TM/unit_mix_bonds_rate

var base_unit_instance_id: String = ""
var base_unit_inst: Dictionary = {}
var material_units_array: Array = []

var _texture_cache: Dictionary = {}
var _pedestal_slots: Array[Control] = []

const ENHANCE_GIL_COST_PER_MATERIAL: int = 1000

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
	if classup_button != null:
		classup_button.pressed.connect(_on_classup_pressed)

	for slot in _pedestal_slots:
		var hit_button: Button = slot.get_node_or_null("HitButton") as Button
		if hit_button != null:
			hit_button.pressed.connect(_on_any_pedestal_pressed)

func _refresh_base_unit_ui() -> void:
	base_unit_id_label.text = "Base Instance ID: %s" % base_unit_instance_id
	#base_unit_sprite.texture = _get_unit_texture(base_unit_inst)
	var unit_visual: Control = UNIT_SCENE.instantiate() as Control
	if unit_visual:
		unit_visual.scene_size = "large"
		unit_visual.unit_data_to_load = base_unit_inst
		unit_visual.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		base_unit_sprite.add_child(unit_visual)
	_display_unit_stats(base_unit_inst)
	_refresh_classup_button_state()

func _refresh_classup_button_state() -> void:
	if classup_button == null:
		return
	var current_rarity: int = int(base_unit_inst.get("current_rarity"))
	var unit_data: Dictionary = base_unit_inst
	var max_rarity: int = int(unit_data.get("rarity_max", 5))
	classup_button.disabled = current_rarity >= max_rarity

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

	_update_get_exp_display()
	_update_need_gil_display()

func _update_get_exp_display() -> void:
	if get_exp_number_label == null:
		return

	if base_unit_inst.is_empty():
		get_exp_number_label.text = "0"
		return

	var base_unit_data: Dictionary = base_unit_inst
	if base_unit_data.is_empty():
		get_exp_number_label.text = "0"
		return

	var base_unit_type: String = str(UnitService.call("_get_unit_type", base_unit_data))
	if base_unit_type == "trust_material":
		get_exp_number_label.text = "0"
		return

	var total_xp_gain: int = 0
	for material_unit_value in material_units_array:
		if not (material_unit_value is Dictionary):
			continue

		var material_unit: Dictionary = material_unit_value
		var material_unit_data: Dictionary = GameDatabase.get_unit(material_unit.get("unitId"))
		if material_unit_data.is_empty():
			continue

		var gains_value: Variant = UnitService.call("_calculate_material_enhance_gains", material_unit, material_unit_data)
		if gains_value is Dictionary:
			total_xp_gain += int((gains_value as Dictionary).get("xp_gain", 0))

	get_exp_number_label.text = "%d" % total_xp_gain

func _update_need_gil_display() -> void:
	if need_gil_number_label == null:
		return

	var required_gil: int = material_units_array.size() * ENHANCE_GIL_COST_PER_MATERIAL
	need_gil_number_label.text = "%d" % required_gil

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
	if base_unit_instance_id == "" or material_units_array.is_empty():
		_show_result_popup("Select a base unit and at least one material unit.")
		return

	var material_ids: Array = []
	for entry: Variant in material_units_array:
		if not (entry is Dictionary):
			continue
		var iid: String = str(entry.get("instance_id", ""))
		if iid != "":
			material_ids.append(iid)

	if material_ids.is_empty():
		_show_result_popup("No valid material units selected.")
		return

	var previous_trust_value: float = float(base_unit_inst.get("trust_value", 0.0))

	confirm_button.disabled = true

	var result: Dictionary = UnitService.enhance_unit(base_unit_instance_id, material_ids)

	confirm_button.disabled = false

	if result.get("success", false):
		var updated: Dictionary = result.get("enhanced_unit", {})
		var consumed_count: int = (result.get("consumed_material_ids", []) as Array).size()
		var gil: int = int(result.get("updated_currency", {}).get("gil", 0))
		var updated_trust_value: float = float(updated.get("trust_value", previous_trust_value))
		var reached_max_trust_now: bool = previous_trust_value < 100.0 and updated_trust_value >= 100.0
		var msg: String = (
			"Enhancement successful!\n"
			+ "Level: %d   XP: %d\n"
			+ "Trust: %.1f%%   LB Level: %d   LB XP: %d\n"
			+ "Consumed: %d unit(s)\n"
			+ "Gil remaining: %d"
		) % [
			int(updated.get("level", 0)),
			int(updated.get("xp", 0)),
			float(updated.get("trust_value", 0.0)),
			int(updated.get("limitburst_level", 0)),
			int(updated.get("limitburst_xp", 0)),
			consumed_count,
			gil
		]

		var trust_reward: Dictionary = result.get("granted_trust_reward", {})
		var unlocked_reward_name: String = ""
		if not trust_reward.is_empty():
			var reward_type: String = str(trust_reward.get("reward_type", ""))
			var reward_template_id: String = str(trust_reward.get("template_id", ""))
			if reward_template_id != "":
				var reward_name: String = "%s %s" % [reward_type, reward_template_id]
				if reward_type == "EQUIP":
					var eq_reward: Dictionary = GameDatabase.get_equipment(reward_template_id)
					if not eq_reward.is_empty():
						reward_name = str(eq_reward.get("name", reward_name))
				elif reward_type == "MATERIA":
					var materia_data = GameDatabase.get_materia(int(reward_template_id))
					if not materia_data.is_empty():
						reward_name = str(materia_data.get("name", reward_name))
				unlocked_reward_name = reward_name
				msg += "\nTrust Master Reward acquired: %s" % reward_name

		if reached_max_trust_now:
			if unlocked_reward_name == "":
				unlocked_reward_name = _resolve_trust_reward_name(base_unit_inst)
			if unlocked_reward_name != "":
				msg += "\nTrust Master reached 100%%!\nUnlocked: %s" % unlocked_reward_name
			else:
				msg += "\nTrust Master reached 100%%!"

		var trust_reward_warning: String = str(result.get("trust_reward_warning", ""))
		if trust_reward_warning != "":
			msg += "\nTrust Reward Warning: %s" % trust_reward_warning

		base_unit_inst.merge(updated, true)
		_refresh_base_unit_ui()
		material_units_array.clear()
		_redraw_material_slots()
		_show_result_popup(msg)
	else:
		var error_msg: String = result.get("error", "Enhancement failed. Please try again.")
		_show_result_popup("Enhancement failed:\n%s" % error_msg)

func _show_result_popup(message: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Enhancement Result"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _on_cancel_pressed() -> void:
	UIManager.pop()
	var new_top: Node = UIManager.get_current_scene()
	if new_top and new_top.has_method("_on_enhance_units"):
		new_top.call_deferred("_on_enhance_units")

func _on_classup_pressed() -> void:
	if base_unit_instance_id == "":
		return
	UIManager.pop()
	UIManager.push("awaken_ui", {
		"base_unit_instance_id": base_unit_instance_id,
		"base_unit_inst": base_unit_inst,
	})

func _get_unit_texture(unit_inst: Dictionary) -> Texture2D:
	if unit_inst.is_empty():
		return null

	var entry_id: String = str(unit_inst.get("unitId"))
	if entry_id == "":
		return null

	var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % entry_id
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
	var xpForNextLevel: int = UnitService.calculate_next_xp_for_unit(unit_inst)
	UnitLevel.text += " / " + str(maxLevel) + "   next " + str(xpForNextLevel)
	var lb_id = str(unit_inst.get("limitburst_id", ""))
	var lb_data: Dictionary = GameDatabase.get_limitburst(lb_id) if lb_id != "" else {}
	if not lb_data.is_empty():
		LBName.text = lb_data.get("name", "Unknown Limit Burst")
	else:
		LBName.text = "None"
	
	var tmr_data = unit_inst.get("trustMasterReward")
	tmr_data = tmr_data.split(":") if not tmr_data == null else null
	if tmr_data != null and tmr_data.size() >= 2:
		var tmr_type = tmr_data[0]
		var tmr_id = str(int(tmr_data[1]))
		var tmr_name = "Unknown Reward"

		if tmr_type == "21":
			var eq_data = GameDatabase.get_equipment(tmr_id)
			if not eq_data.is_empty():
				tmr_name = eq_data.get("name", tmr_name)
		elif tmr_type == "22":
			var mat_data = GameDatabase.get_materia(int(tmr_id))
			if not mat_data.is_empty():
				tmr_name = mat_data.get("name", tmr_name)
			
		TMName.text = tmr_name
	else:
		TMName.text = "None"
	
	TMValue.text = str(unit_inst.get("trust_value"))

	# Recalculate fresh so equipment/esper changes from other screens are reflected,
	# and persist back to keep unit_inst["final_stats"] as the single source of truth.
	var fresh_final_stats: Dictionary = StatCalculator.calculate_final_stats(unit_inst)
	unit_inst["final_stats"] = fresh_final_stats
	var stats: Dictionary = fresh_final_stats.get("stats", {})

	HP.text = str(stats.get("HP"))
	MP.text = str(stats.get("MP"))
	ATK.text = str(stats.get("ATK"))
	DEF.text = str(stats.get("DEF"))
	MAG.text = str(stats.get("MAG"))
	SPR.text = str(stats.get("SPR"))

func _resolve_trust_reward_name(unit_inst: Dictionary) -> String:
	var tmr_data: Variant = unit_inst.get("trustMasterReward", null)
	tmr_data.split(":")
	if tmr_data == null:
		return ""

	var tmr_array: Array = tmr_data
	if tmr_array.size() < 2:
		return ""

	var tmr_type: String = str(tmr_array[0])
	var tmr_id: String = str(tmr_array[1])
	if tmr_id == "":
		return ""

	if tmr_type == "21":
		var eq_data: Dictionary = GameDatabase.get_equipment(tmr_id)
		if not eq_data.is_empty():
			return str(eq_data.get("name", ""))

	if tmr_type == "22":
		var mat_data: Dictionary = GameDatabase.get_materia(int(tmr_id))
		if not mat_data.is_empty():
			return str(mat_data.get("name", ""))

	return ""
