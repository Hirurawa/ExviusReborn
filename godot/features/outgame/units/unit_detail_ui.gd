extends Control

const MagicScene = preload("res://features/shared/Skill.tscn")

@onready var illustration_button: TextureButton = $VBoxContainer/CharInfoHBox/IllustrationButton
@onready var unit_detail_sprite: TextureRect = $VBoxContainer/CharInfoHBox/IllustrationButton/SpritePlaceholder
@onready var anim_sprite: Sprite2D = $VBoxContainer/CharInfoHBox/IllustrationButton/AnimSprite
@onready var unit_detail_back_button: Button = $VBoxContainer/TopBar/BackButton
@onready var unit_detail_name_label: Label = $VBoxContainer/TopBar/TitleBox/NameLabel
@onready var unit_detail_rarity_label: Label = $VBoxContainer/TopBar/TitleBox/InfoHBox/RarityLabel
@onready var unit_detail_level_label: Label = $VBoxContainer/CharInfoHBox/StatsVBox/LevelHBox/LevelLabel
@onready var unit_detail_next_xp_label: Label = $VBoxContainer/CharInfoHBox/StatsVBox/LevelHBox/NextXPLabel
@onready var unit_detail_hp_value: Label = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/HPValue
@onready var unit_detail_mp_value: Label = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/MPValue
@onready var unit_detail_atk_value: Label = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/ATKValue
@onready var unit_detail_def_value: Label = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/DEFValue
@onready var unit_detail_mag_value: Label = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/MAGValue
@onready var unit_detail_spr_value: Label = $VBoxContainer/CharInfoHBox/StatsVBox/StatsGrid/SPRValue
@onready var unit_detail_equip_icons_grid: GridContainer = $VBoxContainer/CharInfoHBox/StatsVBox/EquipIconsGrid
@onready var unit_detail_add_xp_button: Button = $VBoxContainer/ActionsHBox/AddXPButton
@onready var unit_detail_awaken_button: Button = $VBoxContainer/ActionsHBox/AwakenButton

@onready var unit_detail_traits_btn: Button = $VBoxContainer/TabsHBox/TraitButton
@onready var unit_detail_magic_btn: Button = $VBoxContainer/TabsHBox/MagicButton
@onready var unit_detail_special_btn: Button = $VBoxContainer/TabsHBox/SpecialButton
@onready var unit_detail_equipment_tab_btn: Button = $VBoxContainer/TabsHBox/EquipmentTabButton
@onready var unit_detail_ability_tab_btn: Button = $VBoxContainer/TabsHBox/AbilityTabButton
@onready var unit_detail_trait_content: VBoxContainer = $VBoxContainer/TraitContent
@onready var unit_detail_magic_content: ScrollContainer = $VBoxContainer/MagicContent
@onready var unit_detail_special_content: ScrollContainer = $VBoxContainer/SpecialContent
@onready var unit_detail_magic_grid: GridContainer = $VBoxContainer/MagicContent/MagicGrid
@onready var unit_detail_special_grid: GridContainer = $VBoxContainer/SpecialContent/SpecialGrid
@onready var unit_detail_equip_btn: Button = $VBoxContainer/TabsHBox/EquipButton
@onready var unit_detail_equipment_content: ScrollContainer = $VBoxContainer/EquipmentContent
@onready var unit_detail_equipment_grid: GridContainer = $VBoxContainer/EquipmentContent/EquipmentGrid
@onready var unit_detail_ability_content: ScrollContainer = $VBoxContainer/AbilityContent
@onready var unit_detail_ability_grid: GridContainer = $VBoxContainer/AbilityContent/AbilityGrid

@onready var elem_resist_grid: GridContainer = $VBoxContainer/TraitContent/ElementResistGrid
@onready var status_resist_grid: GridContainer = $VBoxContainer/TraitContent/StatusResistGrid
@onready var lb_name_label: Label = $VBoxContainer/TraitContent/LimitBurstHBox/LBName
@onready var tm_name_label: Label = $VBoxContainer/TraitContent/TrustMasterHBox/TMInfoVBox/TMName
@onready var tm_icon_rect: TextureRect = $VBoxContainer/TraitContent/TrustMasterHBox/TMIcon

var current_unit_inst: Dictionary = {}

var _current_major_mode: String = "Equip"
var _current_stats_sub_tab: String = "Equipment"
var _current_equip_sub_tab: String = "Traits"
var _is_animating: bool = false

var _texture_cache: Dictionary = {}

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _ready() -> void:
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

	var level = unit_inst.get("level", 1)
	var max_level = StatCalculator.RARITY_MAX_LEVELS.get(int(rarity), 15)
	unit_detail_level_label.text = "Lvl %d/%d" % [level, max_level]

	var next_xp = unit_inst.get("next_xp", 0)
	unit_detail_next_xp_label.text = "next %d" % next_xp

	var final_stats = unit_inst["final_stats"].get("stats", {})

	unit_detail_hp_value.text = str(final_stats.get("HP", 0))
	unit_detail_mp_value.text = str(final_stats.get("MP", 0))
	unit_detail_atk_value.text = str(final_stats.get("ATK", 0))
	unit_detail_def_value.text = str(final_stats.get("DEF", 0))
	unit_detail_mag_value.text = str(final_stats.get("MAG", 0))
	unit_detail_spr_value.text = str(final_stats.get("SPR", 0))

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

	# Fetch and display the traits directly from the hydrated unit instance
	var element_resist = unit_inst["final_stats"].get("element_resist", {})
	for elem in StatCalculator.ELEMENTS:
		if elem_resist_grid.has_node(elem):
			var resist_panel = elem_resist_grid.get_node(elem)
			var label = resist_panel.get_node("VBox/ValPanel/Label")
			var val = element_resist.get(elem, 0)
			if val != 0:
				label.text = str(int(val)) + "%"
			else:
				label.text = "-"

	var status_resist = unit_inst["final_stats"].get("status_resist", {})
	for status in StatCalculator.STATUSES:
		if status_resist_grid.has_node(status):
			var resist_panel = status_resist_grid.get_node(status)
			var label = resist_panel.get_node("VBox/ValPanel/Label")
			var val = status_resist.get(status, 0)
			if val != 0:
				label.text = str(int(val)) + "%"
			else:
				label.text = "-"

	var lb_id = str(int(unit_inst.get("limitburst_id", "")))
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


func _populate_skills(unit_inst: Dictionary, unit_data: Dictionary) -> void:
	for child in unit_detail_magic_grid.get_children():
		child.queue_free()
	for child in unit_detail_special_grid.get_children():
		child.queue_free()
		
	if (not unit_inst.has("final_stats") or not unit_inst["final_stats"].has("skills")):
		return
		
	var all_skills = unit_inst["final_stats"]["skills"]

	# 2. Populate Magic (Goes to Magic Grid)
	var magic_list = all_skills.get("magic", [])
	for sk in magic_list:
		var sk_id = str(sk.get("id", ""))
		if DataManager.game_data_skills_magic.has(sk_id):
			var panel = MagicScene.instantiate()
			panel.setup_from_skill_data(DataManager.game_data_skills_magic[sk_id], sk.get("source", "Trait"), false)
			unit_detail_magic_grid.add_child(panel)

	# 3. Populate Abilities (Goes to Special Grid)
	var ability_list = all_skills.get("ability", [])
	for sk in ability_list:
		var sk_id = str(sk.get("id", ""))
		if DataManager.game_data_skills_ability.has(sk_id):
			var panel = MagicScene.instantiate()
			#panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			panel.setup_from_skill_data(DataManager.game_data_skills_ability[sk_id], sk.get("source", "Trait"), false)
			unit_detail_special_grid.add_child(panel)

	# 4. Populate Passives (Goes to Special Grid)
	var passive_list = all_skills.get("passive", [])
	for sk in passive_list:
		var sk_id = str(sk.get("id", ""))
		if DataManager.game_data_skills_passive.has(sk_id):
			var panel = MagicScene.instantiate()
			#panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			panel.setup_from_skill_data(DataManager.game_data_skills_passive[sk_id], sk.get("source", "Trait"), false)
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
			var template_id = DataManager.get_equipment_template_id(item_id)
			var item_data = DataManager.game_data_equipment.get(template_id, {})
			btn.text = slot_info.name + ": " + item_data.get("name", "Unknown")
		else:
			btn.text = slot_info.name + ": Empty"

		var other_hand = "l_hand" if slot_info.id == "r_hand" else "r_hand"
		if slot_info.id in ["r_hand", "l_hand"]:
			var other_item_id = equipment.get(other_hand, "")
			if other_item_id != "":
				var other_template_id = DataManager.get_equipment_template_id(other_item_id)
				var other_item_data = DataManager.game_data_equipment.get(other_template_id, {})
				if other_item_data.get("is_twohanded", false):
					btn.text = slot_info.name + ": Locked"
					btn.disabled = true

		btn.pressed.connect(_on_equip_slot_clicked.bind(unit_inst, slot_info.id, slot_info.types))
		unit_detail_equipment_grid.add_child(btn)

	# Fetch ability slots directly from the hydrated unit instance (fallback to unit_data)
	var ability_slots = unit_inst.get("ability_slots", unit_data.get("ability_slots", 1))

	for i in range(ability_slots):
		var slot_id = "ability_" + str(i + 1)
		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 60)
		var item_id = equipment.get(slot_id, "")
		if item_id != "":
			var template_id = DataManager.get_equipment_template_id(item_id)
			var item_data = DataManager.game_data_equipment.get(template_id, {})
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

	var allowed_equip: Array = unit_data.get("equip", [])
	var equip_icons_data: Dictionary = DataManager.game_data_equipment_icons

	var valid_keys: Array = []
	for key in equip_icons_data.keys():
		var type_id: int = equip_icons_data[key].get("type_id", 0)
		if type_id < 60:
			valid_keys.append(key)

	valid_keys.sort_custom(func(a, b): return int(a) < int(b))

	for key in valid_keys:
		var item: Dictionary = equip_icons_data[key]
		var type_id: int = item.get("type_id", 0)
		var icon_name: String = item.get("icon", "")
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

	var anim_data: Dictionary = TextureBuilder.load_unit_animation_data(unit_id)
	if anim_data.is_empty():
		return

	var frames: Array[Texture2D] = anim_data.get("frames", [])
	var frame_delays: Array = anim_data.get("delays", [])
	var frame_width: int = anim_data.get("frame_width", 0)
	var frame_height: int = anim_data.get("frame_height", 0)
	var num_frames: int = anim_data.get("num_frames", 0)

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
