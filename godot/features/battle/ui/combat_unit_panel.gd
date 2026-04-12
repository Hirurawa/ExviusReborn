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
	if battle_manager:
		if not battle_manager.unit_stats_updated.is_connected(_on_unit_stats_updated):
			battle_manager.unit_stats_updated.connect(_on_unit_stats_updated)
		if not battle_manager.unit_acted.is_connected(_on_unit_acted):
			battle_manager.unit_acted.connect(_on_unit_acted)
		if not battle_manager.turn_changed.is_connected(_on_turn_changed):
			battle_manager.turn_changed.connect(_on_turn_changed)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var battle_manager: Node = get_tree().root.find_child("BattleManager", true, false)
		if battle_manager:
			battle_manager.execute_queued_action(_my_index)

func setup(unit_index: int) -> void:
	_my_index = unit_index
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	var battle_manager: Node = get_tree().root.find_child("BattleManager", true, false)
	if battle_manager:
		battle_manager.request_unit_stats(_my_index)

func _on_unit_acted(index: int) -> void:
	if index == _my_index:
		modulate = Color(0.5, 0.5, 0.5, 1.0)

func _on_turn_changed(_new_turn: int) -> void:
	modulate = Color(1.0, 1.0, 1.0, 1.0)

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
