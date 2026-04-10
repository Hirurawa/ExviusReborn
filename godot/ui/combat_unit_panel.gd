extends PanelContainer

@onready var name_label = %NameLabel
@onready var hp_label = %HPLabel
@onready var mp_label = %MPLabel
@onready var hp_bar = %HPBar
@onready var mp_bar = %MPBar
@onready var limit_bar = %LimitBar

func setup(unit_data: Dictionary) -> void:
	var template_id = str(unit_data.get("unit_id", ""))
	var template = DataManager.game_data_units.get(template_id, {})

	name_label.text = template.get("name", "Unknown")

	var cur_hp = unit_data.get("current_hp", 0)
	var max_hp = unit_data.get("max_hp", 1)
	hp_label.text = "%d / %d" % [cur_hp, max_hp]
	hp_bar.max_value = max_hp
	hp_bar.value = cur_hp

	var cur_mp = unit_data.get("current_mp", 0)
	var max_mp = unit_data.get("max_mp", 1)
	mp_label.text = "%d / %d" % [cur_mp, max_mp]
	mp_bar.max_value = max_mp
	mp_bar.value = cur_mp

	limit_bar.max_value = unit_data.get("max_limit", 100)
	limit_bar.value = unit_data.get("limit_gauge", 0)
