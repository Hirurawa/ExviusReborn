extends Control

const MagicScene: PackedScene = preload("res://features/shared/Skill.tscn")

@onready var back_button: TextureButton = $UnitNamebgChara/UnitMinibutton1

# --- Selector ---
@onready var selector_containter: VBoxContainer = $AbilityAwakeningSelector
@onready var skill_grid: GridContainer = $AbilityAwakeningSelector/SkillList

@onready var unit_detail_name_label: Label = $AbilityAwakeningSelector/unit_statusbg/UnitName
@onready var unit_detail_rarity_label: Label = $AbilityAwakeningSelector/unit_statusbg/RarityStarsLabel
@onready var unit_detail_level_label: Label = $AbilityAwakeningSelector/unit_statusbg/UnitLevel/UnitLevel
@onready var unit_detail_level_next_exp_label: Label = $AbilityAwakeningSelector/unit_statusbg/UnitLevel/UnitLvupInfo2/NextExpLabel
@onready var unit_detail_exp_bar: TextureProgressBar = $AbilityAwakeningSelector/unit_statusbg/UnitLevel/UnitExpBg/UnitExpBar
@onready var unit_detail_hp_value: Label = $AbilityAwakeningSelector/unit_statusbg/unit_status_label_hp/unit_status_ext_hp_now_number
@onready var unit_detail_mp_value: Label = $AbilityAwakeningSelector/unit_statusbg/unit_status_label_mp/unit_status_ext_mp_now_number
@onready var unit_detail_atk_value: Label = $AbilityAwakeningSelector/unit_statusbg/unit_status_label_attack/unit_status_ext_attack_now_number
@onready var unit_detail_def_value: Label = $AbilityAwakeningSelector/unit_statusbg/unit_status_label_defense/unit_status_ext_defense_now_number
@onready var unit_detail_mag_value: Label = $AbilityAwakeningSelector/unit_statusbg/unit_status_label_magic/unit_status_ext_magic_now_number
@onready var unit_detail_spr_value: Label = $AbilityAwakeningSelector/unit_statusbg/unit_status_label_mnd/unit_status_ext_mnd_now_number

@onready var unit_detail_pedestal: TextureRect = $AbilityAwakeningSelector/unit_statusbg/unit_charastand_large

# --- Awakening ---
@onready var awakening_containter: Control = $AbilityAwakening
@onready var gil_label: Label = $AbilityAwakening/Button/unit_classup_need_money_number
@onready var awaken_button: TextureButton = $AbilityAwakening/Button/unit_classup_button_evo
@onready var before_skill_texture: Control = $AbilityAwakening/SkillInfo/sublimation_frame_1/Control
@onready var before_desc: Label = $AbilityAwakening/SkillInfo/sublimation_frame_detail_1
@onready var after_skill_texture: Control = $AbilityAwakening/SkillInfo/sublimation_frame_2/Control
@onready var after_desc: RichTextLabel = $AbilityAwakening/SkillInfo/sublimation_frame_detail_2
@onready var result_text_label: Label = $AbilityAwakening/Button/unit_classup_check_result_text

@onready var material_nodes: Array[Control] = [
	$AbilityAwakening/Materials/Material1,
	$AbilityAwakening/Materials/Material2,
	$AbilityAwakening/Materials/Material3,
	$AbilityAwakening/Materials/Material4,
	$AbilityAwakening/Materials/Material5,
]

enum Depth { SELECTOR, AWAKENING }
var current_depth: Depth = Depth.SELECTOR

var _texture_cache: Dictionary = {}

var before_skill_id: int = -1
var unit_instance: Dictionary = {}
var awakening: Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	awaken_button.pressed.connect(_on_awaken_pressed)
	#init_scene({"unit_instance": GameDatabase.get_unit(253000807)})


func init_scene(params: Dictionary) -> void:
	if params.has("base_unit"):
		unit_instance = params.get("base_unit")
	
	_populate_skill_list()
	_unit_details()


# --- SELECTOR ---

func _populate_skill_list() -> void:
	for child in skill_grid.get_children():
		child.queue_free()
	
	var skills = GameDatabase.get_unit_awakenable_skills(unit_instance.get("unitSeries"))
	for skill in skills:
		var skill_data = GameDatabase.get_magic(skill.get("beforeSkillId"))
		var button: Button = Button.new()
		button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.z_index = 18
		var add_button: bool = false
		var panel: Control = MagicScene.instantiate()
		# TODO: Make "temp" prettier. It looks like a mess.
		var temp = unit_instance.get("final_stats").get("skills").get("magic").filter(func(x): return x["id"] == str(skill.get("beforeSkillId")))
		if not skill_data.is_empty() and not temp.is_empty():
			panel.setup_from_skill_data(skill_data, "Trait", temp[0].get("awaken_level"), false)
			add_button = true
		else:
			skill_data = GameDatabase.get_ability(skill.get("beforeSkillId"))
			temp = unit_instance.get("final_stats").get("skills").get("ability").filter(func(x): return x["id"] == str(skill.get("beforeSkillId")))
			if not skill_data.is_empty() and not temp.is_empty():
				panel.setup_from_skill_data(skill_data, "Trait", temp[0].get("awaken_level"), false)
				add_button = true
			else:
				skill_data = GameDatabase.get_passive(skill.get("beforeSkillId"))
				temp = unit_instance.get("final_stats").get("skills").get("passive").filter(func(x): return x["id"] == str(skill.get("beforeSkillId")))
				if not skill_data.is_empty() and not temp.is_empty():
					panel.setup_from_skill_data(skill_data, "Trait", temp[0].get("awaken_level"), false)
					add_button = true
					
		if add_button:
			button.pressed.connect(_on_skill_clicked.bind(skill.get("beforeSkillId")))
			panel.add_child(button)
			skill_grid.add_child(panel)


func _unit_details() -> void:
	var rarity: int = int(unit_instance.get("current_rarity", 1))
	var pedestal_img_path: String = "res://assets/ui/unit/unit_charastand_rare%s_large.tres" % str(rarity)
	var pedestal_tex: Texture2D = load(pedestal_img_path) as Texture2D
	unit_detail_pedestal.texture = pedestal_tex
	var max_rarity: int = int(unit_instance.get("rarity_max", 5))
	var stars: String = ""
	for i in range(rarity):
		stars += "★"
	for i in range(max_rarity - rarity):
		stars += "☆"
	unit_detail_rarity_label.text = stars

	var level: int = int(unit_instance.get("level", 1))
	var max_level: int = int(StatCalculator.RARITY_MAX_LEVELS.get(rarity, 15))
	var next_xp: int = UnitService.calculate_next_xp_for_unit(unit_instance)
	unit_detail_level_label.text = "%d/%d" % [level, max_level]
	unit_detail_level_next_exp_label.text = str(next_xp)
	var xp = unit_instance.get("xp")
	var progress: Dictionary = UnitService.level_progress_at_xp(unit_instance, xp)
	var level_floor: float = float(progress.get("level_floor", 0))
	var span: float = maxf(1.0, float(progress.get("next_floor", 1)) - level_floor)
	var into_level: float = clampf(xp - level_floor, 0.0, span)
	unit_detail_exp_bar.max_value = span
	unit_detail_exp_bar.value = into_level
	
	var final_stats: Dictionary = unit_instance.get("final_stats", {}).get("stats", {})
	var hp: int = int(final_stats.get("HP", 0))
	var mp: int = int(final_stats.get("MP", 0))
	var atk: int = int(final_stats.get("ATK", 0))
	var def: int = int(final_stats.get("DEF", 0))
	var mag: int = int(final_stats.get("MAG", 0))
	var spr: int = int(final_stats.get("SPR", 0))

	unit_detail_hp_value.text = str(hp)
	unit_detail_mp_value.text = str(mp)
	unit_detail_atk_value.text = str(atk)
	unit_detail_def_value.text = str(def)
	unit_detail_mag_value.text = str(mag)
	unit_detail_spr_value.text = str(spr)
	
	unit_detail_name_label.text = str(unit_instance.get("unitName", "Unknown"))


func _on_skill_clicked(skill_id: int) -> void:
	current_depth = Depth.AWAKENING
	before_skill_id = skill_id
	awakening = GameDatabase.get_skill_awakening_info(before_skill_id)
	_refresh_skill_textures()
	_populate_awakening_requirements()
	_refresh_button_state()
	selector_containter.visible = false
	awakening_containter.visible = true


# --- Awakening ---

# TODO: Make prettier. This is a mess.
func _refresh_skill_textures() -> void:
	var before_panel: Control = MagicScene.instantiate()
	var after_panel: Control = MagicScene.instantiate()
	var after_skill_data
	var before_skill_data = GameDatabase.get_magic(before_skill_id)
	if awakening.get("beforeExplain") != null:
		before_desc.text = awakening.get("beforeExplain")
	after_desc.text = awakening.get("afterExplain")
	var temp = unit_instance.get("final_stats").get("skills").get("magic").filter(func(x): return x["id"] == str(before_skill_id))
	if not before_skill_data.is_empty():
		before_panel.setup_from_skill_data(before_skill_data, "Trait", temp[0].get("awaken_level"))
		before_skill_texture.add_child(before_panel)
		after_skill_data = GameDatabase.get_magic(awakening.get("afterSkillId"))
		after_panel.setup_from_skill_data(after_skill_data, "Trait", int(temp[0].get("awaken_level"))+1)
		after_skill_texture.add_child(after_panel)
	else:
		before_skill_data = GameDatabase.get_ability(before_skill_id)
		temp = unit_instance.get("final_stats").get("skills").get("ability").filter(func(x): return x["id"] == str(before_skill_id))
		if not before_skill_data.is_empty():
			before_panel.setup_from_skill_data(before_skill_data, "Trait", temp[0].get("awaken_level"))
			before_skill_texture.add_child(before_panel)
			after_skill_data = GameDatabase.get_ability(awakening.get("afterSkillId"))
			after_panel.setup_from_skill_data(after_skill_data, "Trait", int(temp[0].get("awaken_level"))+1)
			after_skill_texture.add_child(after_panel)
		else:
			before_skill_data = GameDatabase.get_passive(before_skill_id)
			temp = unit_instance.get("final_stats").get("skills").get("passive").filter(func(x): return x["id"] == str(before_skill_id))
			if not before_skill_data.is_empty():
				before_panel.setup_from_skill_data(before_skill_data, "Trait", temp[0].get("awaken_level"))
				before_skill_texture.add_child(before_panel)
				after_skill_data = GameDatabase.get_passive(awakening.get("afterSkillId"))
				after_panel.setup_from_skill_data(after_skill_data, "Trait", int(temp[0].get("awaken_level"))+1)
				after_skill_texture.add_child(after_panel)


func _populate_awakening_requirements() -> void:
	if gil_label != null:
		gil_label.text = str(int(awakening.get("gil", 0)))

	var materials: Dictionary = {}
	for item in str(awakening.get("material", "")).split(',', false):
		var parts := item.split(":")
		if parts.size() >= 3:
			materials[parts[1]] = parts[2].to_int()
	var material_ids: Array = materials.keys()

	var stackables_var: Variant = InventoryService.owned_items.get("stackables", {})
	var stackables: Dictionary = stackables_var as Dictionary if stackables_var is Dictionary else {}

	for i in range(material_nodes.size()):
		var slot: Control = material_nodes[i]
		if slot == null:
			continue
		if i >= material_ids.size():
			slot.visible = false
			continue
		var item_id: int = int(material_ids[i])
		var count: int = int(materials[material_ids[i]])
		var item_data: Dictionary = GameDatabase.get_item(item_id)

		var icon_node: TextureRect = slot.get_node_or_null("unit_classup_item_icon") as TextureRect
		if icon_node != null:
			var icon_name: String = str(item_data.get("iconFile", ""))
			var tex: Texture2D = null
			if icon_name != "":
				tex = _load_cached_texture("res://assets/items/" + icon_name)
			icon_node.texture = tex

		var num_node: Label = slot.get_node_or_null("unit_classup_item_num") as Label
		if num_node != null:
			num_node.text = "x " + str(count)

		var name_node: Label = slot.get_node_or_null("unit_classup_item_name") as Label
		if name_node != null:
			name_node.text = str(item_data.get("name", item_id))

		var have_node: Label = slot.get_node_or_null("unit_classup_item_have") as Label
		if have_node != null:
			var owned_count: int = int(stackables.get(str(item_id), 0))
			have_node.text = str(owned_count)
			if owned_count < count:
				have_node.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
			else:
				have_node.remove_theme_color_override("font_color")

		slot.visible = true


func _load_cached_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not ResourceLoader.exists(path):
		_texture_cache[path] = null
		return null
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex


func _refresh_button_state() -> void:
	var status: Dictionary = UnitService.can_awaken_ability(before_skill_id)
	var can_awaken: bool = bool(status.get("ok", false))
	var reason: String = str(status.get("reason", ""))

	if awaken_button != null:
		awaken_button.visible = true
		awaken_button.disabled = not can_awaken
	if result_text_label != null:
		if can_awaken:
			result_text_label.visible = false
		else:
			result_text_label.text = reason
			result_text_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
			result_text_label.visible = reason != ""


func _on_awaken_pressed() -> void:
	var response: Dictionary = UnitService.awaken_ability(before_skill_id, unit_instance.get("instance_id"))
	if bool(response.get("success", false)):
		before_skill_id = awakening.get("afterSkillId")
		awakening = GameDatabase.get_skill_awakening_info(before_skill_id)
		unit_instance = UnitService.owned_units_ids.filter(func(x): return x.instance_id == unit_instance.get("instance_id"))[0]
		_show_result_popup("Awakening successful!")
		if awakening.is_empty():
			_on_back_pressed()
			return
		_populate_awakening_requirements()
		_refresh_button_state()
		_refresh_skill_textures()
	else:
		_show_result_popup(str(response.get("error", "Awakening failed")))


func _show_result_popup(message: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Awakening Result"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)


func _on_back_pressed() -> void:
	match current_depth:
		Depth.AWAKENING:
			current_depth = Depth.SELECTOR
			selector_containter.visible = true
			awakening_containter.visible = false
			_populate_skill_list()
			_unit_details()
		Depth.SELECTOR:
			UIManager.pop()
