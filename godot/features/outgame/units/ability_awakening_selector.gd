extends Control

const MagicScene: PackedScene = preload("res://features/shared/Skill.tscn")

@onready var back_button: Button = $UnitNamebgChara/UnitMinibutton1
@onready var skill_grid: GridContainer = $VBoxContainer/SkillList

@onready var unit_detail_name_label: Label = $VBoxContainer/unit_statusbg/UnitName
@onready var unit_detail_rarity_label: Label = $VBoxContainer/unit_statusbg/RarityStarsLabel
@onready var unit_detail_level_label: Label = $VBoxContainer/unit_statusbg/UnitLevel/UnitLevel
@onready var unit_detail_level_next_exp_label: Label = $VBoxContainer/unit_statusbg/UnitLevel/UnitLvupInfo2/NextExpLabel
@onready var unit_detail_exp_bar: TextureProgressBar = $VBoxContainer/unit_statusbg/UnitLevel/UnitExpBg/UnitExpBar
@onready var unit_detail_hp_value: Label = $VBoxContainer/unit_statusbg/unit_status_label_hp/unit_status_ext_hp_now_number
@onready var unit_detail_mp_value: Label = $VBoxContainer/unit_statusbg/unit_status_label_mp/unit_status_ext_mp_now_number
@onready var unit_detail_atk_value: Label = $VBoxContainer/unit_statusbg/unit_status_label_attack/unit_status_ext_attack_now_number
@onready var unit_detail_def_value: Label = $VBoxContainer/unit_statusbg/unit_status_label_defense/unit_status_ext_defense_now_number
@onready var unit_detail_mag_value: Label = $VBoxContainer/unit_statusbg/unit_status_label_magic/unit_status_ext_magic_now_number
@onready var unit_detail_spr_value: Label = $VBoxContainer/unit_statusbg/unit_status_label_mnd/unit_status_ext_mnd_now_number

@onready var unit_detail_pedestal: TextureRect = $VBoxContainer/unit_statusbg/unit_charastand_large

var unit_inst: Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	var temp_unit_inst = GameDatabase.get_unit(253000807)
	#init_scene({"unit_inst": temp_unit_inst})


func init_scene(params: Dictionary) -> void:
	if params.has("unit_inst"):
		unit_inst = params.get("unit_inst", {})
	
		_populate_skill_list()
		_unit_details()


func _populate_skill_list() -> void:
	var skills = GameDatabase.get_unit_awakenable_skills(unit_inst.get("unitSeries"), unit_inst.get("current_rarity"), unit_inst.get("level"))
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
		var temp = unit_inst.get("final_stats").get("skills").get("magic").filter(func(x): return x["id"] == str(skill.get("beforeSkillId")))
		if not skill_data.is_empty() and not temp.is_empty():
			panel.setup_from_skill_data(skill_data, "Trait", temp[0].get("awaken_level"), false)
			add_button = true
		else:
			skill_data = GameDatabase.get_ability(skill.get("beforeSkillId"))
			temp = unit_inst.get("final_stats").get("skills").get("ability").filter(func(x): return x["id"] == str(skill.get("beforeSkillId")))
			if not skill_data.is_empty() and not temp.is_empty():
				panel.setup_from_skill_data(skill_data, "Trait", temp[0].get("awaken_level"), false)
				add_button = true
			else:
				skill_data = GameDatabase.get_passive(skill.get("beforeSkillId"))
				temp = unit_inst.get("final_stats").get("skills").get("passive").filter(func(x): return x["id"] == str(skill.get("beforeSkillId")))
				if not skill_data.is_empty() and not temp.is_empty():
					panel.setup_from_skill_data(skill_data, "Trait", temp[0].get("awaken_level"), false)
					add_button = true
					
		if add_button:
			button.pressed.connect(_on_skill_clicked.bind(skill.get("beforeSkillId")))
			panel.add_child(button)
			skill_grid.add_child(panel)


func _unit_details() -> void:
	var rarity: int = int(unit_inst.get("current_rarity", 1))
	var pedestal_img_path: String = "res://assets/ui/unit/unit_charastand_rare%s_large.tres" % str(rarity)
	var pedestal_tex: Texture2D = load(pedestal_img_path) as Texture2D
	unit_detail_pedestal.texture = pedestal_tex
	var max_rarity: int = int(unit_inst.get("rarity_max", 5))
	var stars: String = ""
	for i in range(rarity):
		stars += "★"
	for i in range(max_rarity - rarity):
		stars += "☆"
	unit_detail_rarity_label.text = stars

	var level: int = int(unit_inst.get("level", 1))
	var max_level: int = int(StatCalculator.RARITY_MAX_LEVELS.get(rarity, 15))
	var next_xp: int = UnitService.calculate_next_xp_for_unit(unit_inst)
	unit_detail_level_label.text = "%d/%d" % [level, max_level]
	unit_detail_level_next_exp_label.text = str(next_xp)
	var xp = unit_inst.get("xp")
	var progress: Dictionary = UnitService.level_progress_at_xp(unit_inst, xp)
	var level_floor: float = float(progress.get("level_floor", 0))
	var span: float = maxf(1.0, float(progress.get("next_floor", 1)) - level_floor)
	var into_level: float = clampf(xp - level_floor, 0.0, span)
	unit_detail_exp_bar.max_value = span
	unit_detail_exp_bar.value = into_level
	
	var final_stats: Dictionary = unit_inst.get("final_stats", {}).get("stats", {})
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
	
	unit_detail_name_label.text = str(unit_inst.get("unitName", "Unknown"))


func _on_skill_clicked(skill_id: int) -> void:
	UIManager.push("awaken_ability_ui", {"before_skill_id": skill_id, "unit_instance": unit_inst})


func _on_back_pressed() -> void:
	UIManager.pop()
