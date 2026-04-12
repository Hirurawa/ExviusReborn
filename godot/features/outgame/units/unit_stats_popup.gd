extends Control

@onready var name_label: Label = $Panel/VBoxContainer/NameLabel
@onready var level_label: Label = $Panel/VBoxContainer/LevelLabel
@onready var hp_label: Label = $Panel/VBoxContainer/StatsContainer/HPLabel
@onready var mp_label: Label = $Panel/VBoxContainer/StatsContainer/MPLabel
@onready var atk_label: Label = $Panel/VBoxContainer/StatsContainer/ATKLabel
@onready var def_label: Label = $Panel/VBoxContainer/StatsContainer/DEFLabel
@onready var mag_label: Label = $Panel/VBoxContainer/StatsContainer/MAGLabel
@onready var spr_label: Label = $Panel/VBoxContainer/StatsContainer/SPRLabel

@onready var close_btn: Button = $Panel/VBoxContainer/CloseButton
@onready var swap_btn: Button = $Panel/VBoxContainer/SwapButton
@onready var remove_btn: Button = $Panel/VBoxContainer/RemoveButton

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
	close_btn.pressed.connect(_on_close_pressed)
	swap_btn.pressed.connect(_on_swap_pressed)
	remove_btn.pressed.connect(_on_remove_pressed)

func _populate_data() -> void:
	if current_unit_inst.is_empty():
		return

	var unit_id: String = current_unit_inst.get("unit_id", "")
	var unit_data: Dictionary = DataManager.game_data_units.get(unit_id, {})

	name_label.text = unit_data.get("name", "Unknown")
	level_label.text = "Level: %s" % current_unit_inst.get("level", 1)

	var final_stats: Dictionary = current_unit_inst.get("final_stats", {})

	hp_label.text = "HP: " + str(final_stats.get("HP", 0))
	mp_label.text = "MP: " + str(final_stats.get("MP", 0))
	atk_label.text = "ATK: " + str(final_stats.get("ATK", 0))
	def_label.text = "DEF: " + str(final_stats.get("DEF", 0))
	mag_label.text = "MAG: " + str(final_stats.get("MAG", 0))
	spr_label.text = "SPR: " + str(final_stats.get("SPR", 0))

func _on_close_pressed() -> void:
	UIManager.pop()

func _on_swap_pressed() -> void:
	UIManager.pop()
	UIManager.push("unit_selector_ui", {"mode": "select", "party_index": target_party_index, "slot_index": target_slot_index})

func _on_remove_pressed() -> void:
	DataManager.assign_unit_to_party(target_party_index, target_slot_index, "")
	UIManager.pop()
