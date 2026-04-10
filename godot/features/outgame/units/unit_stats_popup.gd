extends Control

@onready var name_label = $Panel/VBoxContainer/NameLabel
@onready var level_label = $Panel/VBoxContainer/LevelLabel
@onready var hp_label = $Panel/VBoxContainer/StatsContainer/HPLabel
@onready var mp_label = $Panel/VBoxContainer/StatsContainer/MPLabel
@onready var atk_label = $Panel/VBoxContainer/StatsContainer/ATKLabel
@onready var def_label = $Panel/VBoxContainer/StatsContainer/DEFLabel
@onready var mag_label = $Panel/VBoxContainer/StatsContainer/MAGLabel
@onready var spr_label = $Panel/VBoxContainer/StatsContainer/SPRLabel

@onready var close_btn = $Panel/VBoxContainer/CloseButton
@onready var swap_btn = $Panel/VBoxContainer/SwapButton

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

func _ready():
	close_btn.pressed.connect(_on_close_pressed)
	swap_btn.pressed.connect(_on_swap_pressed)

func _populate_data():
	if current_unit_inst.is_empty():
		return

	var unit_id = current_unit_inst.get("unit_id", "")
	var unit_data = DataManager.game_data_units.get(unit_id, {})

	name_label.text = unit_data.get("name", "Unknown")
	level_label.text = "Level: %s" % current_unit_inst.get("level", 1)

	# Fetch stats similarly to unit detail (simplification here)
	# Proper stat calc requires reading equip, base, and rarity
	# For popup we can fetch pre-calc or defaults
	hp_label.text = "HP: ???"
	mp_label.text = "MP: ???"
	atk_label.text = "ATK: ???"
	def_label.text = "DEF: ???"
	mag_label.text = "MAG: ???"
	spr_label.text = "SPR: ???"

func _on_close_pressed():
	UIManager.pop()

func _on_swap_pressed():
	UIManager.pop()
	UIManager.push("unit_selector_ui", {"mode": "select", "party_index": target_party_index, "slot_index": target_slot_index})
