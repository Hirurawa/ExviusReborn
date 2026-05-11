extends Control

const MagicScene: PackedScene = preload("res://features/shared/Skill.tscn")
const ItemScene: PackedScene = preload("res://features/shared/Item.tscn")
const UNIT_ANIM_TARGET_HEIGHT: float = 128.0
const TAB_SMALL_TEXTURE_NORMAL: Texture2D = preload("res://assets/ui/unit/unit_status_button.tres")
const TAB_SMALL_TEXTURE_ON: Texture2D = preload("res://assets/ui/unit/unit_status_button_on.tres")
const TAB_BIG_TEXTURE_NORMAL: Texture2D = preload("res://assets/ui/unit/unit_status_button_big.tres")
const TAB_BIG_TEXTURE_ON: Texture2D = preload("res://assets/ui/unit/unit_status_button_big_on.tres")

@onready var illustration_button: TextureButton = $IllustrationButton
@onready var unit_detail_sprite: TextureRect = $IllustrationButton/unit_charastand_large/unit_chara
@onready var anim_sprite: Sprite2D = $IllustrationButton/AnimSprite
@onready var unit_detail_back_button: TextureButton = $UnitNamebgChara2/BackButton
@onready var unit_detail_name_label: Label = $unit_sublimation_name
@onready var unit_detail_rarity_label: Label = $RarityStarsLabel
@onready var unit_detail_level_label: Label = $unit_sublimation_number
@onready var unit_detail_hp_value: Label = $unit_statusbg/unit_status_label_hp/unit_status_ext_hp_now_number
@onready var unit_detail_hp_max_value: Label = $unit_statusbg/unit_status_label_hp/unit_status_ext_hp_max_number
@onready var unit_detail_mp_value: Label = $unit_statusbg/unit_status_label_mp/unit_status_ext_mp_now_number
@onready var unit_detail_mp_max_value: Label = $unit_statusbg/unit_status_label_mp/unit_status_ext_mp_max_number
@onready var unit_detail_atk_value: Label = $unit_statusbg/unit_status_label_attack/unit_status_ext_attack_now_number
@onready var unit_detail_atk_max_value: Label = $unit_statusbg/unit_status_label_attack/unit_status_ext_attack_max_number
@onready var unit_detail_def_value: Label = $unit_statusbg/unit_status_label_defense/unit_status_ext_defense_now_number
@onready var unit_detail_def_max_value: Label = $unit_statusbg/unit_status_label_defense/unit_status_ext_defense_max_number
@onready var unit_detail_mag_value: Label = $unit_statusbg/unit_status_label_magic/unit_status_ext_magic_now_number
@onready var unit_detail_mag_max_value: Label = $unit_statusbg/unit_status_label_magic/unit_status_ext_magic_max_number
@onready var unit_detail_spr_value: Label = $unit_statusbg/unit_status_label_mnd/unit_status_ext_mnd_now_number
@onready var unit_detail_spr_max_value: Label = $unit_statusbg/unit_status_label_mnd/unit_status_ext_mnd_max_number
@onready var unit_detail_equip_icons_grid: GridContainer = $unit_statusbg/EquipIconsGrid

@onready var unit_detail_equip_btn: TextureButton = $unit_status_button_equip
@onready var unit_detail_equip_btn_label_equip: TextureRect = $unit_status_button_equip/unit_status_button_label_equip
@onready var unit_detail_equip_btn_label_status: TextureRect = $unit_status_button_equip/unit_status_button_label_status
@onready var equip_header: Control = $EquipHeader
@onready var status_header: Control = $StatusHeader
@onready var unit_detail_traits_btn: TextureButton = $StatusHeader/unit_status_tab_button_trait
@onready var unit_detail_magic_btn: TextureButton = $StatusHeader/unit_status_tab_button_magic
@onready var unit_detail_special_btn: TextureButton = $StatusHeader/unit_status_tab_button_special
@onready var unit_detail_equipment_tab_btn: TextureButton = $EquipHeader/unit_status_tab_button_equipment
@onready var unit_detail_ability_tab_btn: TextureButton = $EquipHeader/unit_status_tab_button_ability

@onready var unit_detail_trait_content: VBoxContainer = $VBoxContainer/TraitContent
@onready var unit_detail_magic_content: ScrollContainer = $ContentLayer/MagicContent
@onready var unit_detail_special_content: ScrollContainer = $ContentLayer/SpecialContent
@onready var unit_detail_magic_grid: GridContainer = $ContentLayer/MagicContent/MagicGrid
@onready var unit_detail_special_grid: GridContainer = $ContentLayer/SpecialContent/SpecialGrid
@onready var unit_detail_equipment_content: ScrollContainer = $ContentLayer/EquipmentContent
@onready var unit_detail_equipment_grid: GridContainer = $ContentLayer/EquipmentContent/EquipmentGrid
@onready var unit_detail_ability_content: ScrollContainer = $ContentLayer/AbilityContent
@onready var unit_detail_ability_grid: GridContainer = $ContentLayer/AbilityContent/AbilityGrid

@onready var elem_resist_grid: GridContainer = $VBoxContainer/TraitContent/UnitResistbg/ElementResistGrid
@onready var status_resist_grid: GridContainer = $VBoxContainer/TraitContent/UnitResistbg/StatusResistGrid
@onready var lb_name_label: Label = $VBoxContainer/TraitContent/unit_detail_limit_offset/LimitBurstLabel
@onready var tm_name_label: Label = $VBoxContainer/TraitContent/UnitBondsbg/unit_mix_bonds_name
@onready var tm_icon_rect: TextureRect = $VBoxContainer/TraitContent/UnitBondsbg/TrustMasterIcon
@onready var tm_percent_value: Label = $VBoxContainer/TraitContent/UnitBondsbg/unit_mix_bonds_rate

var current_unit_inst: Dictionary = {}

var _current_major_mode: String = "Equip"
var _current_stats_sub_tab: String = "Equipment"
var _current_equip_sub_tab: String = "Traits"
var _idle_anim_token: int = 0

var _texture_cache: Dictionary = {}

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _ready() -> void:
	unit_detail_back_button.pressed.connect(_on_back_pressed)
	illustration_button.pressed.connect(_on_illustration_pressed)
	unit_detail_equip_btn.pressed.connect(_on_unit_detail_equip_btn_pressed)
	unit_detail_equipment_tab_btn.pressed.connect(_on_unit_detail_equipment_tab_btn_pressed)
	unit_detail_ability_tab_btn.pressed.connect(_on_unit_detail_ability_tab_btn_pressed)
	unit_detail_traits_btn.pressed.connect(_on_unit_detail_traits_btn_pressed)
	unit_detail_magic_btn.pressed.connect(_on_unit_detail_magic_btn_pressed)
	unit_detail_special_btn.pressed.connect(_on_unit_detail_special_btn_pressed)

	if not UnitService.units_updated.is_connected(_on_units_updated):
		UnitService.units_updated.connect(_on_units_updated)

	_apply_current_mode_state()

func _exit_tree() -> void:
	_stop_idle_animation()
	if UnitService.units_updated.is_connected(_on_units_updated):
		UnitService.units_updated.disconnect(_on_units_updated)

func init_scene(params: Dictionary) -> void:
	if params.has("unit_inst"):
		current_unit_inst = params["unit_inst"]
		_show_unit_detail(current_unit_inst)

func _on_back_pressed() -> void:
	UIManager.pop()

func _on_units_updated(units: Array) -> void:
	if current_unit_inst.has("instance_id"):
		for u in units:
			if u.get("instance_id") == current_unit_inst.get("instance_id"):
				current_unit_inst = u
				_show_unit_detail(current_unit_inst)
				break

func _show_unit_detail(unit_inst: Dictionary) -> void:
	_stop_idle_animation()

	var unit_id: String = str(unit_inst.get("unit_id", ""))
	var unit_data: Dictionary = StaticData.game_data_units.get(unit_id, {})

	unit_detail_name_label.text = str(unit_data.get("name", "Unknown"))

	var img_path: String = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
	var tex: Texture2D = load(img_path) as Texture2D
	unit_detail_sprite.texture = tex
	_show_idle_or_static(unit_id)

	var rarity: int = int(unit_inst.get("current_rarity", 1))
	var max_rarity: int = int(unit_data.get("rarity_max", 5))
	var stars: String = ""
	for i in range(rarity):
		stars += "★"
	for i in range(max_rarity - rarity):
		stars += "☆"
	unit_detail_rarity_label.text = stars

	var level: int = int(unit_inst.get("level", 1))
	var max_level: int = int(StatCalculator.RARITY_MAX_LEVELS.get(rarity, 15))
	var next_xp: int = int(unit_inst.get("next_xp", 0))
	unit_detail_level_label.text = "Lvl %d/%d  next %d" % [level, max_level, next_xp]

	# Recalculate stats fresh to reflect current equipment/esper assignments,
	# and persist back so other screens (enhance_ui, etc.) read up-to-date data.
	var fresh_final_stats: Dictionary = StatCalculator.calculate_final_stats(unit_inst)
	unit_inst["final_stats"] = fresh_final_stats
	var final_stats: Dictionary = fresh_final_stats.get("stats", {})
	var hp: int = int(final_stats.get("HP", 0))
	var mp: int = int(final_stats.get("MP", 0))
	var atk: int = int(final_stats.get("ATK", 0))
	var dfn: int = int(final_stats.get("DEF", 0))
	var mag: int = int(final_stats.get("MAG", 0))
	var spr: int = int(final_stats.get("SPR", 0))

	unit_detail_hp_value.text = str(hp)
	unit_detail_hp_max_value.text = "/%d" % hp
	unit_detail_mp_value.text = str(mp)
	unit_detail_mp_max_value.text = "/%d" % mp
	unit_detail_atk_value.text = str(atk)
	unit_detail_atk_max_value.text = "/%d" % atk
	unit_detail_def_value.text = str(dfn)
	unit_detail_def_max_value.text = "/%d" % dfn
	unit_detail_mag_value.text = str(mag)
	unit_detail_mag_max_value.text = "/%d" % mag
	unit_detail_spr_value.text = str(spr)
	unit_detail_spr_max_value.text = "/%d" % spr

	_populate_equip_icons_grid(unit_data)
	_populate_skills(fresh_final_stats)
	_populate_equipment_slots(unit_inst, unit_data)
	_populate_resistances(fresh_final_stats)
	_populate_lb_and_tmr(unit_inst, unit_data)
	_apply_current_mode_state()

func _show_idle_or_static(unit_id: String) -> void:
	if unit_id == "":
		_show_static_illustration()
		return

	var anim_data: Dictionary = TextureBuilder.load_unit_animation_data(unit_id, "idle")
	var payload: Dictionary = _get_animation_payload(anim_data)
	if payload.is_empty():
		_show_static_illustration()
		return

	_idle_anim_token += 1
	var token: int = _idle_anim_token

	unit_detail_sprite.hide()
	anim_sprite.texture = payload["frames"][0] as Texture2D
	anim_sprite.show()
	_fit_anim_sprite(int(payload["frame_width"]), int(payload["frame_height"]))
	_run_idle_loop(token, payload["frames"], payload["delays"])

func _play_attack_then_resume_idle(unit_id: String) -> void:
	if unit_id == "":
		return

	var anim_data: Dictionary = TextureBuilder.load_unit_animation_data(unit_id, "atk")
	var payload: Dictionary = _get_animation_payload(anim_data)
	if payload.is_empty():
		_show_idle_or_static(unit_id)
		return

	_idle_anim_token += 1
	var token: int = _idle_anim_token

	unit_detail_sprite.hide()
	anim_sprite.texture = payload["frames"][0] as Texture2D
	anim_sprite.show()
	_fit_anim_sprite(int(payload["frame_width"]), int(payload["frame_height"]))
	_run_attack_once(token, unit_id, payload["frames"], payload["delays"])

func _get_animation_payload(anim_data: Dictionary) -> Dictionary:
	if anim_data.is_empty():
		return {}

	var raw_frames: Array = anim_data.get("frames", [])
	var frames: Array[Texture2D] = []
	for frame in raw_frames:
		var frame_tex: Texture2D = frame as Texture2D
		if frame_tex != null:
			frames.append(frame_tex)

	var frame_width: int = int(anim_data.get("frame_width", 0))
	var frame_height: int = int(anim_data.get("frame_height", 0))
	if frame_width <= 0 or frame_height <= 0 or frames.is_empty():
		return {}

	return {
		"frames": frames,
		"delays": anim_data.get("delays", []),
		"frame_width": frame_width,
		"frame_height": frame_height
	}

func _show_static_illustration() -> void:
	anim_sprite.hide()
	anim_sprite.texture = null
	unit_detail_sprite.show()

func _fit_anim_sprite(frame_width: int, frame_height: int) -> void:
	var fit_w: float = maxf(1.0, illustration_button.size.x)
	var fit_h: float = maxf(1.0, illustration_button.size.y)
	var scale_factor: float = UNIT_ANIM_TARGET_HEIGHT / float(frame_height)
	if scale_factor <= 0.0:
		scale_factor = min(fit_w / float(frame_width), fit_h / float(frame_height))
	anim_sprite.scale = Vector2(scale_factor, scale_factor)
	anim_sprite.position = Vector2(fit_w * 0.5, fit_h * 0.5)

func _run_idle_loop(token: int, frames: Array[Texture2D], frame_delays: Array) -> void:
	while is_instance_valid(self) and is_inside_tree() and token == _idle_anim_token:
		for i in range(frames.size()):
			if not is_instance_valid(self) or token != _idle_anim_token:
				return
			anim_sprite.texture = frames[i]
			var delay: float = 0.05
			if i < frame_delays.size():
				delay = float(frame_delays[i]) / 60.0
			await get_tree().create_timer(delay).timeout

func _run_attack_once(token: int, unit_id: String, frames: Array[Texture2D], frame_delays: Array) -> void:
	for i in range(frames.size()):
		if not is_instance_valid(self) or token != _idle_anim_token:
			return
		anim_sprite.texture = frames[i]
		var delay: float = 0.05
		if i < frame_delays.size():
			delay = float(frame_delays[i]) / 60.0
		await get_tree().create_timer(delay).timeout

	if not is_instance_valid(self) or token != _idle_anim_token:
		return
	_show_idle_or_static(unit_id)

func _stop_idle_animation() -> void:
	_idle_anim_token += 1

func _populate_resistances(final_stats: Dictionary) -> void:
	var element_resist: Dictionary = final_stats.get("element_resist", {})
	for elem in StatCalculator.ELEMENTS:
		if elem_resist_grid.has_node(elem):
			var resist_panel: Node = elem_resist_grid.get_node(elem)
			var label: Label = resist_panel.get_node("VBox/ValPanel/Label") as Label
			var val: int = int(element_resist.get(elem, 0))
			label.text = str(val) + "%" if val != 0 else "-"

	var status_resist: Dictionary = final_stats.get("status_resist", {})
	var status_node_map: Dictionary = {
		"POISON": "POISON",
		"BLIND": "BLIND",
		"SLEEP": "SLEEP",
		"SILENCE": "SILENCE",
		"PARALYSIS": "PARALYSIS",
		"CONFUSION": "CONFUSION",
		"CONFUSE": "CONFUSION",
		"DISEASE": "DISEASE",
		"PETRIFY": "PETRIFY",
		"PETRIFICATION": "PETRIFY"
	}

	for status_key in status_node_map.keys():
		var node_name: String = str(status_node_map[status_key])
		if status_resist_grid.has_node(node_name):
			var panel: Node = status_resist_grid.get_node(node_name)
			var label: Label = panel.get_node("VBox/ValPanel/Label") as Label
			var val: int = int(status_resist.get(status_key, 0))
			label.text = str(val) + "%" if val != 0 else "-"

func _populate_lb_and_tmr(unit_inst: Dictionary, unit_data: Dictionary) -> void:
	var lb_id: String = str(int(unit_inst.get("limitburst_id", "0")))
	if lb_id != "0" and StaticData.game_data_limitbursts.has(lb_id):
		var lb_name: String = str(StaticData.game_data_limitbursts[lb_id].get("name", "Unknown Limit Burst"))
		lb_name_label.text = "Limit Burst: %s" % lb_name
	else:
		lb_name_label.text = "Limit Burst: None"

	var tmr_data: Variant = unit_data.get("TMR")
	if tmr_data == null or typeof(tmr_data) != TYPE_ARRAY or tmr_data.size() < 2:
		tm_name_label.text = "Trust Master: None"
		tm_icon_rect.texture = null
		return
	
	tm_percent_value.text = str(unit_inst.get("trust_value"))
	
	var tmr_type: String = str(tmr_data[0])
	var tmr_id: String = str(int(tmr_data[1]))
	var tmr_name: String = "Unknown Reward"
	var icon_path: String = ""

	if tmr_type == "EQUIP" and StaticData.game_data_equipment.has(tmr_id):
		var eq_data: Dictionary = StaticData.game_data_equipment[tmr_id]
		tmr_name = str(eq_data.get("name", tmr_name))
		icon_path = "res://assets/equip/" + str(eq_data.get("icon", "0.png"))
	elif tmr_type == "MATERIA" and StaticData.game_data_materia.has(tmr_id):
		var mat_data: Dictionary = StaticData.game_data_materia[tmr_id]
		tmr_name = str(mat_data.get("name", tmr_name))
		icon_path = "res://assets/materia/" + str(mat_data.get("icon", "0.png"))

	tm_name_label.text = tmr_name
	if icon_path != "":
		tm_icon_rect.texture = load(icon_path) as Texture2D
	else:
		tm_icon_rect.texture = null

func _populate_skills(final_stats_profile: Dictionary) -> void:
	for child in unit_detail_magic_grid.get_children():
		child.queue_free()
	for child in unit_detail_special_grid.get_children():
		child.queue_free()

	if not final_stats_profile.has("skills"):
		return

	var all_skills: Dictionary = final_stats_profile["skills"]

	var magic_list: Array = all_skills.get("magic", [])
	for sk in magic_list:
		var sk_id: String = str(sk.get("id", ""))
		if StaticData.game_data_skills_magic.has(sk_id):
			var panel: Control = MagicScene.instantiate()
			panel.setup_from_skill_data(StaticData.game_data_skills_magic[sk_id], str(sk.get("source", "Trait")), false)
			unit_detail_magic_grid.add_child(panel)

	var ability_list: Array = all_skills.get("ability", [])
	for sk in ability_list:
		var sk_id: String = str(sk.get("id", ""))
		if StaticData.game_data_skills_ability.has(sk_id):
			var panel: Control = MagicScene.instantiate()
			panel.setup_from_skill_data(StaticData.game_data_skills_ability[sk_id], str(sk.get("source", "Trait")), false)
			unit_detail_special_grid.add_child(panel)

	var passive_list: Array = all_skills.get("passive", [])
	for sk in passive_list:
		var sk_id: String = str(sk.get("id", ""))
		if StaticData.game_data_skills_passive.has(sk_id):
			var panel: Control = MagicScene.instantiate()
			panel.setup_from_skill_data(StaticData.game_data_skills_passive[sk_id], str(sk.get("source", "Trait")), false)
			unit_detail_special_grid.add_child(panel)

func _populate_equipment_slots(unit_inst: Dictionary, unit_data: Dictionary) -> void:
	for child in unit_detail_equipment_grid.get_children():
		child.queue_free()
	for child in unit_detail_ability_grid.get_children():
		child.queue_free()

	var equipment: Dictionary = unit_inst.get("equipment", {})
	var equip_slots: Array[Dictionary] = [
		{"id": "r_hand", "name": "R. Hand", "cat_tex": "rhand", "types": ["Weapon", "Shield"]},
		{"id": "l_hand", "name": "L. Hand", "cat_tex": "lhand", "types": ["Weapon", "Shield"]},
		{"id": "head", "name": "Head", "cat_tex": "head", "types": ["Hat", "Helm"]},
		{"id": "body", "name": "Body", "cat_tex": "body", "types": ["Clothes", "Light Armor", "Heavy Armor", "Robe"]},
		{"id": "acc_1", "name": "Acc 1", "cat_tex": "accessory1", "types": ["Accessory"]},
		{"id": "acc_2", "name": "Acc 2", "cat_tex": "accessory2", "types": ["Accessory"]}
	]

	for slot_info in equip_slots:
		var slot_cell: Control = ItemScene.instantiate()
		slot_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var display_options: Dictionary = {
			"slot_badge": slot_info.cat_tex,
			"type_badge": "",
			"detail_text": ""
		}

		var item_id: String = str(equipment.get(slot_info.id, ""))
		var item_data: Dictionary = {}
		var is_locked: bool = false

		var other_hand: String = "l_hand" if slot_info.id == "r_hand" else "r_hand"
		if slot_info.id in ["r_hand", "l_hand"]:
			var other_item_id: String = str(equipment.get(other_hand, ""))
			if other_item_id != "":
				var other_template_id: String = InventoryService.get_equipment_template_id(other_item_id)
				var other_item_data: Dictionary = StaticData.game_data_equipment.get(other_template_id, {})
				if bool(other_item_data.get("is_twohanded", false)):
					is_locked = true

		if is_locked:
			item_data = {"name": str(slot_info.name), "slot": "", "type": "", "stats": {}}
			display_options["detail_text"] = "Locked"
		else:
			if item_id != "":
				var template_id: String = InventoryService.get_equipment_template_id(item_id)
				item_data = StaticData.game_data_equipment.get(template_id, {}).duplicate()
			else:
				item_data = {"name": "", "slot": "", "type": "", "stats": {}}
				display_options["detail_text"] = "Empty"

		unit_detail_equipment_grid.add_child(slot_cell)
		slot_cell.setup_from_item_data(item_data, display_options)
		slot_cell.set_clickable(not is_locked)

		if is_locked:
			slot_cell.modulate = Color(0.45, 0.45, 0.45, 1.0)
		else:
			slot_cell.modulate = Color(1.0, 1.0, 1.0, 1.0)
			slot_cell.pressed.connect(_on_equip_slot_clicked.bind(unit_inst, str(slot_info.id), slot_info.types))

	var ability_slots: int = int(unit_inst.get("ability_slots", unit_data.get("ability_slots", 1)))
	for i in range(ability_slots):
		var slot_id: String = "ability_" + str(i + 1)
		var slot_cell: Control = ItemScene.instantiate()
		slot_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var item_id: String = str(equipment.get(slot_id, ""))
		var item_data: Dictionary = {}
		var display_options: Dictionary = {
			"slot_badge": "materia" + str(i + 1),
			"type_badge": "",
			"detail_text": ""
		}

		var _is_materia_slot_item: bool = false
		if item_id != "":
			var template_id: String = InventoryService.get_equipment_template_id(item_id)
			if StaticData.game_data_equipment.has(template_id):
				item_data = StaticData.game_data_equipment.get(template_id, {}).duplicate()
			elif StaticData.game_data_materia.has(template_id):
				item_data = StaticData.game_data_materia.get(template_id, {}).duplicate()
				_is_materia_slot_item = true
			else:
				item_data = {"name": "", "slot": "", "type": "", "stats": {}}
				display_options["detail_text"] = "Empty"
		else:
			item_data = {"name": "", "slot": "", "type": "", "stats": {}}
			display_options["detail_text"] = "Empty"

		unit_detail_ability_grid.add_child(slot_cell)
		if _is_materia_slot_item:
			var icon_name: String = str(item_data.get("icon", ""))
			var icon_path: String = "res://assets/abilities/" + icon_name if icon_name != "" else ""
			var effects: Array = item_data.get("effects", [])
			var detail_text: String = str(effects[0]) if not effects.is_empty() else ""
			slot_cell.setup_placeholder(str(item_data.get("name", "Unknown Materia")), detail_text, {"icon_path": icon_path})
		else:
			slot_cell.setup_from_item_data(item_data, display_options)
		slot_cell.set_clickable(true)
		slot_cell.pressed.connect(_on_equip_slot_clicked.bind(unit_inst, slot_id, ["Materia"]))

func _on_equip_slot_clicked(unit_inst: Dictionary, slot_id: String, allowed_types: Array) -> void:
	UIManager.push("equip_selection_popup", {
		"unit_inst": unit_inst,
		"slot_id": slot_id,
		"allowed_types": allowed_types
	})

func _on_unit_detail_equip_btn_pressed() -> void:
	if _current_major_mode == "Equip":
		_current_major_mode = "Stats"
		if _current_stats_sub_tab == "Equipment":
			_on_unit_detail_equipment_tab_btn_pressed()
		else:
			_on_unit_detail_ability_tab_btn_pressed()
	else:
		_current_major_mode = "Equip"
		if _current_equip_sub_tab == "Traits":
			_on_unit_detail_traits_btn_pressed()
		elif _current_equip_sub_tab == "Magic":
			_on_unit_detail_magic_btn_pressed()
		else:
			_on_unit_detail_special_btn_pressed()

func _apply_current_mode_state() -> void:
	equip_header.visible = _current_major_mode == "Stats"
	status_header.visible = _current_major_mode == "Equip"
	unit_detail_equip_btn_label_equip.visible = _current_major_mode == "Equip"
	unit_detail_equip_btn_label_status.visible = _current_major_mode == "Stats"
	_update_tab_button_states()

func _update_tab_button_states() -> void:
	unit_detail_traits_btn.texture_normal = TAB_SMALL_TEXTURE_NORMAL
	unit_detail_traits_btn.texture_pressed = TAB_SMALL_TEXTURE_NORMAL
	unit_detail_magic_btn.texture_normal = TAB_SMALL_TEXTURE_NORMAL
	unit_detail_magic_btn.texture_pressed = TAB_SMALL_TEXTURE_NORMAL
	unit_detail_special_btn.texture_normal = TAB_SMALL_TEXTURE_NORMAL
	unit_detail_special_btn.texture_pressed = TAB_SMALL_TEXTURE_NORMAL

	unit_detail_equipment_tab_btn.texture_normal = TAB_BIG_TEXTURE_NORMAL
	unit_detail_equipment_tab_btn.texture_pressed = TAB_BIG_TEXTURE_NORMAL
	unit_detail_ability_tab_btn.texture_normal = TAB_BIG_TEXTURE_NORMAL
	unit_detail_ability_tab_btn.texture_pressed = TAB_BIG_TEXTURE_NORMAL

	match _current_equip_sub_tab:
		"Traits":
			unit_detail_traits_btn.texture_normal = TAB_SMALL_TEXTURE_ON
			unit_detail_traits_btn.texture_pressed = TAB_SMALL_TEXTURE_ON
		"Magic":
			unit_detail_magic_btn.texture_normal = TAB_SMALL_TEXTURE_ON
			unit_detail_magic_btn.texture_pressed = TAB_SMALL_TEXTURE_ON
		_:
			unit_detail_special_btn.texture_normal = TAB_SMALL_TEXTURE_ON
			unit_detail_special_btn.texture_pressed = TAB_SMALL_TEXTURE_ON

	if _current_stats_sub_tab == "Ability":
		unit_detail_ability_tab_btn.texture_normal = TAB_BIG_TEXTURE_ON
		unit_detail_ability_tab_btn.texture_pressed = TAB_BIG_TEXTURE_ON
	else:
		unit_detail_equipment_tab_btn.texture_normal = TAB_BIG_TEXTURE_ON
		unit_detail_equipment_tab_btn.texture_pressed = TAB_BIG_TEXTURE_ON

func _on_unit_detail_equipment_tab_btn_pressed() -> void:
	_current_major_mode = "Stats"
	_current_stats_sub_tab = "Equipment"
	_apply_current_mode_state()
	unit_detail_trait_content.hide()
	unit_detail_magic_content.hide()
	unit_detail_special_content.hide()
	unit_detail_equipment_content.show()
	unit_detail_ability_content.hide()

func _on_unit_detail_ability_tab_btn_pressed() -> void:
	_current_major_mode = "Stats"
	_current_stats_sub_tab = "Ability"
	_apply_current_mode_state()
	unit_detail_trait_content.hide()
	unit_detail_magic_content.hide()
	unit_detail_special_content.hide()
	unit_detail_equipment_content.hide()
	unit_detail_ability_content.show()

func _on_unit_detail_traits_btn_pressed() -> void:
	_current_major_mode = "Equip"
	_current_equip_sub_tab = "Traits"
	_apply_current_mode_state()
	unit_detail_trait_content.show()
	unit_detail_magic_content.hide()
	unit_detail_special_content.hide()
	unit_detail_equipment_content.hide()
	unit_detail_ability_content.hide()

func _on_unit_detail_magic_btn_pressed() -> void:
	_current_major_mode = "Equip"
	_current_equip_sub_tab = "Magic"
	_apply_current_mode_state()
	unit_detail_trait_content.hide()
	unit_detail_magic_content.show()
	unit_detail_special_content.hide()
	unit_detail_equipment_content.hide()
	unit_detail_ability_content.hide()

func _on_unit_detail_special_btn_pressed() -> void:
	_current_major_mode = "Equip"
	_current_equip_sub_tab = "Special"
	_apply_current_mode_state()
	unit_detail_trait_content.hide()
	unit_detail_magic_content.hide()
	unit_detail_special_content.show()
	unit_detail_equipment_content.hide()
	unit_detail_ability_content.hide()

func _populate_equip_icons_grid(unit_data: Dictionary) -> void:
	for child in unit_detail_equip_icons_grid.get_children():
		child.queue_free()

	var allowed_equip: Array = unit_data.get("equip", [])
	var equip_icons_data: Dictionary = StaticData.game_data_equipment_icons
	var valid_keys: Array = []

	for key in equip_icons_data.keys():
		var type_id: int = int(equip_icons_data[key].get("type_id", 0))
		if type_id < 60:
			valid_keys.append(key)

	valid_keys.sort_custom(func(a, b): return int(a) < int(b))

	for key in valid_keys:
		var item: Dictionary = equip_icons_data[key]
		var type_id: int = int(item.get("type_id", 0))
		var icon_name: String = str(item.get("icon", ""))
		var tex_rect: TextureRect = TextureRect.new()
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(16, 16)
		tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var tex_path: String = "res://assets/icons/equipments/%s" % icon_name
		if ResourceLoader.exists(tex_path):
			tex_rect.texture = _get_dynamic_texture(tex_path)

		if not (type_id in allowed_equip or float(type_id) in allowed_equip):
			tex_rect.modulate = Color(0.3, 0.3, 0.3, 1.0)

		unit_detail_equip_icons_grid.add_child(tex_rect)

func _on_illustration_pressed() -> void:
	if current_unit_inst.is_empty():
		return

	var unit_id: String = str(current_unit_inst.get("unit_id", ""))
	_play_attack_then_resume_idle(unit_id)
