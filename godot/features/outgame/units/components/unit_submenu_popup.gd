extends Control

@onready var overlay: ColorRect = $ColorRect

@onready var close_btn:TextureButton = $btn_close
@onready var equip_btn:TextureButton = $Buttons/btn_equip
@onready var swap_btn: TextureButton = $Buttons/btn_change
@onready var enhance_btn: TextureButton = $Buttons/btn_powerup
@onready var awaken_btn: TextureButton = $Buttons/btn_classup

@onready var unit_name: Label = $unit_menu_unit_name
@onready var rarity_star_container: HBoxContainer = $RarityStars

@onready var unit_detail_level_label: Label = $UnitStatusLabelLv/UnitLevel
@onready var unit_detail_level_next_exp_label: Label = $UnitLvupInfo2/NextExpLabel
@onready var unit_detail_exp_bar: TextureProgressBar = $UnitExpBg/UnitExpBar

@onready var unit_detail_hp_value: Label = $Stats/HP/unit_status_hp_now_number
@onready var unit_detail_hp_max_value: Label = $Stats/HP/unit_status_hp_max_number
@onready var unit_detail_mp_value: Label = $Stats/MP/unit_status_mp_now_number
@onready var unit_detail_mp_max_value: Label = $Stats/MP/unit_status_mp_max_number
@onready var unit_detail_atk_value: Label = $Stats/ATK/unit_status_attack_now_number
@onready var unit_detail_atk_max_value: Label = $Stats/ATK/unit_status_attack_max_number
@onready var unit_detail_def_value: Label = $Stats/DEF/unit_status_defense_now_number
@onready var unit_detail_def_max_value: Label = $Stats/DEF/unit_status_defense_max_number
@onready var unit_detail_mag_value: Label = $Stats/MAG/unit_status_magic_now_number
@onready var unit_detail_mag_max_value: Label = $Stats/MAG/unit_status_magic_max_number
@onready var unit_detail_spr_value: Label = $Stats/SPR/unit_status_mnd_now_number
@onready var unit_detail_spr_max_value: Label = $Stats/SPR/unit_status_mnd_max_number

var current_unit_inst: Dictionary
var target_party_index: int = 0
var target_slot_index: int = 0


func init_scene(params: Dictionary) -> void:
	if params.has("unit_inst"):
		current_unit_inst = params.unit_inst
	if params.has("party_index"):
		target_party_index = params.party_index
	if params.has("slot_index"):
		target_slot_index = params.slot_index
	
	_populate_data()


func _ready() -> void:
	overlay.gui_input.connect(_on_overlay_gui_input)
	close_btn.pressed.connect(_on_close_pressed)
	swap_btn.pressed.connect(_on_swap_pressed)
	equip_btn.pressed.connect(_on_equip_pressed)
	enhance_btn.pressed.connect(_on_enhance_pressed)
	awaken_btn.pressed.connect(_on_awaken_pressed)


func _populate_data() -> void:
	if current_unit_inst.is_empty():
		return
	
	unit_name.text = current_unit_inst.get("unitName")
	
	for i in current_unit_inst.get("current_rarity"):
		rarity_star_container.add_child(rarity_star_container.get_node("rarity_star").duplicate())
	
	var fresh_final_stats: Dictionary = StatCalculator.calculate_final_stats(current_unit_inst)
	current_unit_inst["final_stats"] = fresh_final_stats
	var base_stats = current_unit_inst["final_stats"]["base_stats"]
	var final_stats: Dictionary = fresh_final_stats.get("stats", {})
	var hp: int = int(final_stats.get("HP", 0))
	var mp: int = int(final_stats.get("MP", 0))
	var atk: int = int(final_stats.get("ATK", 0))
	var def: int = int(final_stats.get("DEF", 0))
	var mag: int = int(final_stats.get("MAG", 0))
	var spr: int = int(final_stats.get("SPR", 0))
	
	unit_detail_hp_value.text = str(hp)
	unit_detail_hp_max_value.text = str(hp - int(base_stats["HP"]))
	unit_detail_mp_value.text = str(mp)
	unit_detail_mp_max_value.text = str(mp - int(base_stats["MP"]))
	unit_detail_atk_value.text = str(atk)
	unit_detail_atk_max_value.text = str(atk - int(base_stats["ATK"]))
	unit_detail_def_value.text = str(def)
	unit_detail_def_max_value.text = str(def - int(base_stats["DEF"]))
	unit_detail_mag_value.text = str(mag)
	unit_detail_mag_max_value.text = str(mag - int(base_stats["MAG"]))
	unit_detail_spr_value.text = str(spr)
	unit_detail_spr_max_value.text = str(spr - int(base_stats["SPR"]))
	
	var level: int = int(current_unit_inst.get("level", 1))
	var max_level: int = int(StatCalculator.RARITY_MAX_LEVELS.get(int(current_unit_inst.get("current_rarity", 1)), 15))
	var next_xp: int = UnitService.calculate_next_xp_for_unit(current_unit_inst)
	unit_detail_level_label.text = "%d/%d" % [level, max_level]
	unit_detail_level_next_exp_label.text = str(next_xp)
	var xp = current_unit_inst.get("xp")
	var progress: Dictionary = UnitService.level_progress_at_xp(current_unit_inst, xp)
	var level_floor: float = float(progress.get("level_floor", 0))
	var span: float = maxf(1.0, float(progress.get("next_floor", 1)) - level_floor)
	var into_level: float = clampf(xp - level_floor, 0.0, span)
	unit_detail_exp_bar.max_value = span
	unit_detail_exp_bar.value = into_level


func _on_overlay_gui_input(event: InputEvent) -> void:
	# Check if the player left-clicked the background overlay
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_close_pressed()


func _on_close_pressed() -> void:
	queue_free()


func _on_swap_pressed() -> void:
	queue_free()
	var filter = func(u): return u.get("useType") == 0 && u.get("joinParty") == 1 && not u.instance_id in PartyService.parties[target_party_index].get("units")
	UIManager.push("unit_selector_ui", {
		"mode": ModeSelectPartyMember.new(current_unit_inst, target_party_index, target_slot_index, filter)
	})


func _on_equip_pressed() -> void:
	queue_free()
	UIManager.push("unit_detail_ui", {"unit_inst": current_unit_inst, "mode": "equip"})


func _on_enhance_pressed() -> void:
	queue_free()
	UIManager.push("enhance_ui", {"base_unit": current_unit_inst})


func _on_awaken_pressed() -> void:
	queue_free()
	UIManager.push("awaken_ui", {"base_unit": current_unit_inst})
