extends Control

@onready var illustration_button = $VBoxContainer/CharInfoHBox/IllustrationButton
@onready var unit_detail_sprite = $VBoxContainer/CharInfoHBox/IllustrationButton/SpritePlaceholder
@onready var anim_sprite = $VBoxContainer/CharInfoHBox/IllustrationButton/AnimSprite
@onready var unit_detail_back_button = $VBoxContainer/TopBar/BackButton
@onready var unit_detail_name_label = $VBoxContainer/TopBar/TitleBox/NameLabel
@onready var unit_detail_rarity_label = $VBoxContainer/TopBar/TitleBox/InfoHBox/RarityLabel
@onready var unit_detail_level_label = $VBoxContainer/CharInfoHBox/StatsVBox/LevelHBox/LevelLabel
@onready var unit_detail_next_xp_label = $VBoxContainer/CharInfoHBox/StatsVBox/LevelHBox/NextXPLabel
@onready var unit_detail_hp_value = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/HPValue
@onready var unit_detail_mp_value = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/MPValue
@onready var unit_detail_atk_value = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/ATKValue
@onready var unit_detail_def_value = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/DEFValue
@onready var unit_detail_mag_value = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/MAGValue
@onready var unit_detail_spr_value = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/SPRValue
@onready var unit_detail_equip_icons_grid = $VBoxContainer/CharInfoHBox/StatsVBox/EquipIconsGrid
@onready var unit_detail_add_xp_button = $VBoxContainer/ActionsHBox/AddXPButton
@onready var unit_detail_awaken_button = $VBoxContainer/ActionsHBox/AwakenButton

@onready var unit_detail_traits_btn = $VBoxContainer/TabsHBox/TraitButton
@onready var unit_detail_magic_btn = $VBoxContainer/TabsHBox/MagicButton
@onready var unit_detail_special_btn = $VBoxContainer/TabsHBox/SpecialButton
@onready var unit_detail_equipment_tab_btn = $VBoxContainer/TabsHBox/EquipmentTabButton
@onready var unit_detail_ability_tab_btn = $VBoxContainer/TabsHBox/AbilityTabButton
@onready var unit_detail_trait_content = $VBoxContainer/TraitContent
@onready var unit_detail_magic_content = $VBoxContainer/MagicContent
@onready var unit_detail_special_content = $VBoxContainer/SpecialContent
@onready var unit_detail_magic_grid = $VBoxContainer/MagicContent/MagicGrid
@onready var unit_detail_special_grid = $VBoxContainer/SpecialContent/SpecialGrid
@onready var unit_detail_equip_btn = $VBoxContainer/TabsHBox/EquipButton
@onready var unit_detail_equipment_content = $VBoxContainer/EquipmentContent
@onready var unit_detail_equipment_grid = $VBoxContainer/EquipmentContent/EquipmentGrid
@onready var unit_detail_ability_content = $VBoxContainer/AbilityContent
@onready var unit_detail_ability_grid = $VBoxContainer/AbilityContent/AbilityGrid

@onready var elem_resist_grid = $VBoxContainer/TraitContent/ElementResistGrid
@onready var status_resist_grid = $VBoxContainer/TraitContent/StatusResistGrid
@onready var lb_name_label = $VBoxContainer/TraitContent/LimitBurstHBox/LBName
@onready var tm_name_label = $VBoxContainer/TraitContent/TrustMasterHBox/TMInfoVBox/TMName
@onready var tm_icon_rect = $VBoxContainer/TraitContent/TrustMasterHBox/TMIcon

var current_unit_inst: Dictionary = {}

var _current_major_mode: String = "Equip"
var _current_stats_sub_tab: String = "Equipment"
var _current_equip_sub_tab: String = "Traits"
var _is_animating: bool = false

func _ready():
	unit_detail_back_button.pressed.connect(func(): UIManager.pop())
	illustration_button.pressed.connect(_on_illustration_pressed)

	unit_detail_equipment_tab_btn.pressed.connect(_on_unit_detail_equipment_tab_btn_pressed)
	unit_detail_ability_tab_btn.pressed.connect(_on_unit_detail_ability_tab_btn_pressed)
	unit_detail_equip_btn.pressed.connect(_on_unit_detail_equip_btn_pressed)
	unit_detail_traits_btn.pressed.connect(_on_unit_detail_traits_btn_pressed)
	unit_detail_magic_btn.pressed.connect(_on_unit_detail_magic_btn_pressed)
	unit_detail_special_btn.pressed.connect(_on_unit_detail_special_btn_pressed)

	DataManager.units_updated.connect(_on_units_updated)

func init_scene(params: Dictionary):
	if params.has("unit_inst"):
		current_unit_inst = params["unit_inst"]
		_show_unit_detail(current_unit_inst)

func _on_units_updated(units: Array):
	if current_unit_inst.has("instance_id"):
		for u in units:
			if u.get("instance_id") == current_unit_inst.get("instance_id"):
				current_unit_inst = u
				_show_unit_detail(current_unit_inst)
				break

func _show_unit_detail(unit_inst: Dictionary) -> void:
	var unit_id = unit_inst.get("unit_id", "")
	var unit_data: Dictionary = DataManager.game_data_units.get(unit_id, {})

	unit_detail_name_label.text = unit_data.get("name", "Unknown")

	var img_path = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
	var tex = load(img_path)
	if tex:
		unit_detail_sprite.texture = tex
	else:
		unit_detail_sprite.texture = null

	var rarity = unit_inst.get("current_rarity", 1)
	var max_rarity = unit_data.get("rarity_max", 5)
	var stars = ""
	for i in range(rarity):
		stars += "★"
	for i in range(max_rarity - rarity):
		stars += "☆"
	unit_detail_rarity_label.text = stars

	var rarity_max_levels = {
		1: 15,
		2: 30,
		3: 40,
		4: 60,
		5: 80,
		6: 100,
		7: 120
	}

	var level = unit_inst.get("level", 1)
	var max_level = rarity_max_levels.get(int(rarity), 15)
	unit_detail_level_label.text = "Lvl %d/%d" % [level, max_level]

	var next_xp = unit_inst.get("next_xp", 0)
	unit_detail_next_xp_label.text = "next %d" % next_xp

	var entries = unit_data.get("entries", {})
	var entry = entries.get(str(unit_id), entries.get(str(rarity), {}))

	for key in entries.keys():
		if entries[key].get("rarity") == rarity:
			entry = entries[key]
			break

	var stats = entry.get("stats", {})
	var hp = 0
	var mp = 0
	var atk = 0
	var def_stat = 0
	var mag = 0
	var spr = 0

	if not stats.is_empty():
		for stat_name in ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]:
			var stat_arr = stats.get(stat_name, [0, 0])
			if stat_arr.size() >= 2:
				var min_stat = stat_arr[0]
				var max_stat = stat_arr[1]
				var current_stat = min_stat
				if max_level > 1:
					current_stat = min_stat + (level - 1) * float(max_stat - min_stat) / (max_level - 1)

				if stat_name == "HP": hp = round(current_stat)
				elif stat_name == "MP": mp = round(current_stat)
				elif stat_name == "ATK": atk = round(current_stat)
				elif stat_name == "DEF": def_stat = round(current_stat)
				elif stat_name == "MAG": mag = round(current_stat)
				elif stat_name == "SPR": spr = round(current_stat)

	var equip_hp = 0
	var equip_mp = 0
	var equip_atk = 0
	var equip_def = 0
	var equip_mag = 0
	var equip_spr = 0

	var equipment = unit_inst.get("equipment", {})
	for slot_id in equipment:
		var item_id = equipment[slot_id]
		if item_id != "":
			var item_data = DataManager.game_data_equipment.get(item_id, {})
			var item_stats = item_data.get("stats", {})
			equip_hp += item_stats.get("HP", 0)
			equip_mp += item_stats.get("MP", 0)
			equip_atk += item_stats.get("ATK", 0)
			equip_def += item_stats.get("DEF", 0)
			equip_mag += item_stats.get("MAG", 0)
			equip_spr += item_stats.get("SPR", 0)

	unit_detail_hp_value.text = str(int(hp + equip_hp))
	unit_detail_mp_value.text = str(int(mp + equip_mp))
	unit_detail_atk_value.text = str(int(atk + equip_atk))
	unit_detail_def_value.text = str(int(def_stat + equip_def))
	unit_detail_mag_value.text = str(int(mag + equip_mag))
	unit_detail_spr_value.text = str(int(spr + equip_spr))

	_populate_equip_icons_grid(unit_data)

	for connection in unit_detail_add_xp_button.pressed.get_connections():
		unit_detail_add_xp_button.pressed.disconnect(connection["callable"])

	for connection in unit_detail_awaken_button.pressed.get_connections():
		unit_detail_awaken_button.pressed.disconnect(connection["callable"])

	var instance_id = unit_inst.get("instance_id", "")
	unit_detail_add_xp_button.pressed.connect(_on_unit_add_xp_pressed.bind(instance_id))
	unit_detail_awaken_button.pressed.connect(_on_unit_awaken_pressed.bind(instance_id))

	_populate_skills(unit_inst, unit_data)
	_populate_equipment_slots(unit_inst, unit_data)
	
	# Fetch and display the traits
	var element_resist = entry.get("element_resist", [0,0,0,0,0,0,0,0])
	for i in range(8):
		var resist_panel = elem_resist_grid.get_node("Resist" + str(i+1))
		var label = resist_panel.get_node("VBox/ValPanel/Label")
		if element_resist.size() > i and element_resist[i] != 0:
			label.text = str(int(element_resist[i])) + "%"
		else:
			label.text = "-"

	var status_resist = entry.get("status_resist", [0,0,0,0,0,0,0,0])
	for i in range(8):
		var resist_panel = status_resist_grid.get_node("Resist" + str(i+1))
		var label = resist_panel.get_node("VBox/ValPanel/Label")
		if status_resist.size() > i and status_resist[i] != 0:
			label.text = str(int(status_resist[i])) + "%"
		else:
			label.text = "-"

	var lb_id = str(int(entry.get("limitburst_id", "")))
	if lb_id != "" and DataManager.game_data_limitbursts.has(lb_id):
		lb_name_label.text = DataManager.game_data_limitbursts[lb_id].get("name", "Unknown Limit Burst")
	else:
		lb_name_label.text = "None"

	var tmr_data = unit_data.get("TMR")
	if tmr_data != null and typeof(tmr_data) == TYPE_ARRAY and tmr_data.size() >= 2:
		var tmr_type = tmr_data[0]
		var tmr_id = str(int(tmr_data[1]))
		var tmr_name = "Unknown Reward"
		var icon_path = ""

		if tmr_type == "EQUIP":
			if DataManager.game_data_equipment.has(tmr_id):
				var eq_data = DataManager.game_data_equipment[tmr_id]
				tmr_name = eq_data.get("name", tmr_name)
				icon_path = "res://assets/equip/" + eq_data.get("icon", "0.png")
		elif tmr_type == "MATERIA":
			if DataManager.game_data_materia.has(tmr_id):
				var mat_data = DataManager.game_data_materia[tmr_id]
				tmr_name = mat_data.get("name", tmr_name)
				icon_path = "res://assets/materia/" + mat_data.get("icon", "0.png")

		tm_name_label.text = tmr_name
		if icon_path != "":
			var icon_tex = load(icon_path)
			if icon_tex:
				tm_icon_rect.texture = icon_tex
			else:
				tm_icon_rect.texture = null
	else:
		tm_name_label.text = "None"
		tm_icon_rect.texture = null

	if _current_major_mode == "Equip":
		if _current_equip_sub_tab == "Traits":
			_on_unit_detail_traits_btn_pressed()
		elif _current_equip_sub_tab == "Magic":
			_on_unit_detail_magic_btn_pressed()
		elif _current_equip_sub_tab == "Special":
			_on_unit_detail_special_btn_pressed()
	else:
		if _current_stats_sub_tab == "Equipment":
			_on_unit_detail_equipment_tab_btn_pressed()
		elif _current_stats_sub_tab == "Ability":
			_on_unit_detail_ability_tab_btn_pressed()
			
		# Ensure the correct main buttons are visible
		unit_detail_equip_btn.text = "Stats"
		unit_detail_traits_btn.hide()
		unit_detail_magic_btn.hide()
		unit_detail_special_btn.hide()
		unit_detail_equipment_tab_btn.show()
		unit_detail_ability_tab_btn.show()


func _create_skill_panel(skill_data: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(40, 40)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path = "res://assets/abilities/" + skill_data.get("icon", "ability_1.png")
	var tex = load(icon_path)
	if tex:
		icon_rect.texture = tex
	else:
		var color_rect = ColorRect.new()
		color_rect.custom_minimum_size = Vector2(40, 40)
		color_rect.color = Color(0.3, 0.3, 0.3)
		icon_rect.add_child(color_rect)
	hbox.add_child(icon_rect)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var top_hbox = HBoxContainer.new()
	vbox.add_child(top_hbox)

	var trait_lbl = Label.new()
	trait_lbl.text = "Trait"
	trait_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	trait_lbl.add_theme_font_size_override("font_size", 12)
	top_hbox.add_child(trait_lbl)

	var name_lbl = Label.new()
	name_lbl.text = skill_data.get("name", "Unknown Skill")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(name_lbl)

	var cost = skill_data.get("cost", {})
	if cost.has("MP") and cost["MP"] > 0:
		var mp_lbl = Label.new()
		mp_lbl.text = "MP " + str(int(cost["MP"]))
		mp_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		top_hbox.add_child(mp_lbl)

	var desc_lbl = Label.new()
	var effects = skill_data.get("effects", [])
	if typeof(effects) == TYPE_ARRAY and effects.size() > 0:
		var first_eff = effects[0]
		if typeof(first_eff) == TYPE_ARRAY and first_eff.size() > 0:
			desc_lbl.text = str(first_eff[0])
		elif typeof(first_eff) == TYPE_STRING:
			desc_lbl.text = str(first_eff)
		else:
			desc_lbl.text = "No description."
	else:
		desc_lbl.text = "No description."
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(desc_lbl)

	return panel

func _populate_skills(unit_inst: Dictionary, unit_data: Dictionary) -> void:
	for child in unit_detail_magic_grid.get_children():
		child.queue_free()
	for child in unit_detail_special_grid.get_children():
		child.queue_free()

	var rarity = unit_inst.get("current_rarity", 1)
	var level = unit_inst.get("level", 1)
	var skills = unit_data.get("skills", [])

	for sk in skills:
		var req_rarity = sk.get("rarity", 99)
		var req_level = sk.get("level", 99)

		if int(rarity) > int(req_rarity) or (rarity == req_rarity and level >= req_level):
			var sk_id = str(int(sk.get("id", "")))
			var sk_type = sk.get("type", "")

			if sk_type == "MAGIC":
				if DataManager.game_data_skills_magic.has(sk_id):
					var panel = _create_skill_panel(DataManager.game_data_skills_magic[sk_id])
					unit_detail_magic_grid.add_child(panel)
			elif sk_type == "ABILITY":
				if DataManager.game_data_skills_ability.has(sk_id):
					var panel = _create_skill_panel(DataManager.game_data_skills_ability[sk_id])
					unit_detail_special_grid.add_child(panel)

func _populate_equipment_slots(unit_inst: Dictionary, unit_data: Dictionary) -> void:
	for child in unit_detail_equipment_grid.get_children():
		child.queue_free()
	for child in unit_detail_ability_grid.get_children():
		child.queue_free()

	var equipment = unit_inst.get("equipment", {})

	var equip_slots = [
		{"id": "r_hand", "name": "R. Hand", "types": ["Weapon", "Shield"]},
		{"id": "l_hand", "name": "L. Hand", "types": ["Weapon", "Shield"]},
		{"id": "head", "name": "Head", "types": ["Hat", "Helm"]},
		{"id": "body", "name": "Body", "types": ["Clothes", "Light Armor", "Heavy Armor", "Robe"]},
		{"id": "acc_1", "name": "Acc 1", "types": ["Accessory"]},
		{"id": "acc_2", "name": "Acc 2", "types": ["Accessory"]}
	]

	for slot_info in equip_slots:
		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 60)
		var item_id = equipment.get(slot_info.id, "")
		if item_id != "":
			var item_data = DataManager.game_data_equipment.get(item_id, {})
			btn.text = slot_info.name + ": " + item_data.get("name", "Unknown")
		else:
			btn.text = slot_info.name + ": Empty"

		var other_hand = "l_hand" if slot_info.id == "r_hand" else "r_hand"
		if slot_info.id in ["r_hand", "l_hand"]:
			var other_item_id = equipment.get(other_hand, "")
			if other_item_id != "":
				var other_item_data = DataManager.game_data_equipment.get(other_item_id, {})
				if other_item_data.get("is_twohanded", false):
					btn.text = slot_info.name + ": Locked"
					btn.disabled = true

		btn.pressed.connect(_on_equip_slot_clicked.bind(unit_inst, slot_info.id, slot_info.types))
		unit_detail_equipment_grid.add_child(btn)

	var ability_slots = unit_data.get("ability_slots", 1)
	var entries = unit_data.get("entries", {})
	var rarity = unit_inst.get("current_rarity", 1)
	var entry = entries.get(str(unit_inst.get("unit_id")), entries.get(str(rarity), {}))
	for key in entries.keys():
		if entries[key].get("rarity") == rarity:
			entry = entries[key]
			break
	if entry.has("ability_slots"):
		ability_slots = entry.get("ability_slots")

	for i in range(ability_slots):
		var slot_id = "ability_" + str(i + 1)
		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 60)
		var item_id = equipment.get(slot_id, "")
		if item_id != "":
			var item_data = DataManager.game_data_equipment.get(item_id, {})
			btn.text = "Ability " + str(i+1) + ": " + item_data.get("name", "Unknown")
		else:
			btn.text = "Ability " + str(i+1) + ": Empty"

		btn.pressed.connect(_on_equip_slot_clicked.bind(unit_inst, slot_id, ["Materia"]))
		unit_detail_ability_grid.add_child(btn)

func _on_equip_slot_clicked(unit_inst: Dictionary, slot_id: String, allowed_types: Array) -> void:
	UIManager.push("equip_selection_popup", {
		"unit_inst": unit_inst,
		"slot_id": slot_id,
		"allowed_types": allowed_types
	})

func _on_unit_detail_equip_btn_pressed() -> void:
	if unit_detail_equip_btn.text == "Stats":
		_current_major_mode = "Equip"
		unit_detail_equip_btn.text = "Equip"
		unit_detail_equipment_tab_btn.hide()
		unit_detail_ability_tab_btn.hide()
		unit_detail_traits_btn.show()
		unit_detail_magic_btn.show()
		unit_detail_special_btn.show()
		unit_detail_equipment_content.hide()
		unit_detail_ability_content.hide()
		if _current_equip_sub_tab == "Traits":
			_on_unit_detail_traits_btn_pressed()
		elif _current_equip_sub_tab == "Magic":
			_on_unit_detail_magic_btn_pressed()
		elif _current_equip_sub_tab == "Special":
			_on_unit_detail_special_btn_pressed()
	else:
		_current_major_mode = "Stats"
		unit_detail_equip_btn.text = "Stats"
		unit_detail_traits_btn.hide()
		unit_detail_magic_btn.hide()
		unit_detail_special_btn.hide()
		unit_detail_equipment_tab_btn.show()
		unit_detail_ability_tab_btn.show()
		unit_detail_trait_content.hide()
		unit_detail_magic_content.hide()
		unit_detail_special_content.hide()
		if _current_stats_sub_tab == "Equipment":
			_on_unit_detail_equipment_tab_btn_pressed()
		elif _current_stats_sub_tab == "Ability":
			_on_unit_detail_ability_tab_btn_pressed()

func _on_unit_detail_equipment_tab_btn_pressed() -> void:
	_current_stats_sub_tab = "Equipment"
	unit_detail_equipment_content.show()
	unit_detail_ability_content.hide()

func _on_unit_detail_ability_tab_btn_pressed() -> void:
	_current_stats_sub_tab = "Ability"
	unit_detail_equipment_content.hide()
	unit_detail_ability_content.show()

func _on_unit_detail_traits_btn_pressed() -> void:
	_current_equip_sub_tab = "Traits"
	unit_detail_trait_content.show()
	unit_detail_magic_content.hide()
	unit_detail_special_content.hide()
	unit_detail_equipment_content.hide()
	unit_detail_ability_content.hide()
	unit_detail_equip_btn.text = "Equip"

func _populate_equip_icons_grid(unit_data: Dictionary) -> void:
	for child in unit_detail_equip_icons_grid.get_children():
		child.queue_free()

	var allowed_equip = unit_data.get("equip", [])
	var equip_icons_data = DataManager.game_data_equipment_icons

	var valid_keys = []
	for key in equip_icons_data.keys():
		var type_id = equip_icons_data[key].get("type_id", 0)
		if type_id < 60:
			valid_keys.append(key)

	valid_keys.sort_custom(func(a, b): return int(a) < int(b))

	for key in valid_keys:
		var item = equip_icons_data[key]
		var type_id = item.get("type_id", 0)
		var icon_name = item.get("icon", "")
		var tex_rect = TextureRect.new()
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(16, 16)
		tex_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var tex_path = "res://assets/icons/equipments/%s" % icon_name
		if ResourceLoader.exists(tex_path):
			tex_rect.texture = load(tex_path)

		if not (type_id in allowed_equip or float(type_id) in allowed_equip):
			tex_rect.modulate = Color(0.3, 0.3, 0.3, 1.0)

		unit_detail_equip_icons_grid.add_child(tex_rect)

func _on_unit_detail_magic_btn_pressed() -> void:
	_current_equip_sub_tab = "Magic"
	unit_detail_trait_content.hide()
	unit_detail_magic_content.show()
	unit_detail_special_content.hide()
	unit_detail_equipment_content.hide()
	unit_detail_ability_content.hide()
	unit_detail_equip_btn.text = "Equip"

func _on_unit_detail_special_btn_pressed() -> void:
	_current_equip_sub_tab = "Special"
	unit_detail_trait_content.hide()
	unit_detail_magic_content.hide()
	unit_detail_special_content.show()
	unit_detail_equipment_content.hide()
	unit_detail_ability_content.hide()
	unit_detail_equip_btn.text = "Equip"

func _on_unit_add_xp_pressed(instance_id: String) -> void:
	DataManager.add_unit_xp(instance_id, 1000)

func _on_unit_awaken_pressed(instance_id: String) -> void:
	DataManager.awaken_unit(instance_id)

func _on_illustration_pressed() -> void:
	if _is_animating or current_unit_inst.is_empty():
		return

	var unit_id = current_unit_inst.get("unit_id", "")
	if unit_id == "":
		return

	var png_path = "res://assets/unit_spritesheets/%s-atk.rawpng" % unit_id
	var json_path = "res://assets/unit_spritesheets/%s-atk.json" % unit_id

	if not FileAccess.file_exists(png_path) or not FileAccess.file_exists(json_path):
		return

	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		return

	var json_text = file.get_as_text()
	var json_data = JSON.parse_string(json_text)
	if typeof(json_data) != TYPE_DICTIONARY:
		return

	var frame_rect = json_data.get("frameRect", {})
	var image_width = json_data.get("imageWidth", 0)
	var frame_width = frame_rect.get("width", 0)
	var frame_height = frame_rect.get("height", 0)

	if frame_width <= 0 or image_width <= 0:
		return

	# Load the file as an Image (CPU) instead of Texture (GPU) to bypass Vulkan maximum dimension limits on ultra-wide spritesheets
	var file_bytes = FileAccess.get_file_as_bytes(png_path)
	var image = Image.new()
	var err = image.load_png_from_buffer(file_bytes)
	if err != OK:
		return

	var num_frames = image_width / frame_width
	var frames: Array[Texture2D] = []

	for i in range(num_frames):
		var x = i * frame_width
		var region = image.get_region(Rect2i(x, 0, frame_width, frame_height))
		frames.append(ImageTexture.create_from_image(region))

	_is_animating = true
	unit_detail_sprite.hide()

	anim_sprite.hframes = 1
	anim_sprite.vframes = 1
	anim_sprite.texture = frames[0] if frames.size() > 0 else null
	anim_sprite.show()

	# Scale to fit the 150x150 container roughly, maintaining aspect
	var scale_factor = min(150.0 / frame_width, 150.0 / frame_height)
	anim_sprite.scale = Vector2(scale_factor, scale_factor)

	# Center the sprite
	var scaled_width = frame_width * scale_factor
	var scaled_height = frame_height * scale_factor
	anim_sprite.position = Vector2((150.0 - scaled_width) / 2.0, (150.0 - scaled_height) / 2.0)

	var frame_delays = json_data.get("frameDelays", [])

	for i in range(num_frames):
		anim_sprite.texture = frames[i]
		var delay = 0.05 # default
		if i < frame_delays.size():
			delay = float(frame_delays[i]) / 60.0 # Assuming 60 fps base

		await get_tree().create_timer(delay).timeout
		if not is_instance_valid(self):
			return

	anim_sprite.hide()
	unit_detail_sprite.show()
	_is_animating = false
