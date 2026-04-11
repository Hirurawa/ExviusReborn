extends PanelContainer

@onready var name_label: Label = %NameLabel
@onready var hp_label: Label = %HPLabel
@onready var mp_label: Label = %MPLabel
@onready var hp_bar: ProgressBar = %HPBar
@onready var mp_bar: ProgressBar = %MPBar
@onready var limit_bar: ProgressBar = %LimitBar

var _my_index: int = -1

func _ready() -> void:
	var battle_manager: Node = get_tree().root.find_child("BattleManager", true, false)
	if battle_manager and not battle_manager.unit_stats_updated.is_connected(_on_unit_stats_updated):
		battle_manager.unit_stats_updated.connect(_on_unit_stats_updated)

func setup(unit_index: int) -> void:
	_my_index = unit_index
	var battle_manager: Node = get_tree().root.find_child("BattleManager", true, false)
	if battle_manager:
		battle_manager.request_unit_stats(_my_index)

func _on_unit_stats_updated(index: int, unit_name: String, cur_hp: int, max_hp: int, cur_mp: int, max_mp: int, cur_limit: int, max_limit: int) -> void:
	if index != _my_index:
		return

	name_label.text = unit_name

	hp_label.text = "%d / %d" % [cur_hp, max_hp]
	hp_bar.max_value = max_hp
	hp_bar.value = cur_hp

	mp_label.text = "%d / %d" % [cur_mp, max_mp]
	mp_bar.max_value = max_mp
	mp_bar.value = cur_mp

	limit_bar.max_value = max_limit
	limit_bar.value = cur_limit
