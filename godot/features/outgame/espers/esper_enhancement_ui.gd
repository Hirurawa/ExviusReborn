extends Control

@onready var back_button: TextureButton = $UnitNamebgChara2/BackButton
@onready var summon_mix_item: Control = $summon_mix_item
@onready var summon_mix_bar_lv: Label = $summon_mix_bar_area/summon_mix_bar_lv
@onready var summon_mix_bar_exp: Label = $summon_mix_bar_area/summon_mix_bar_exp

var _summon_id: String = ""
var _summon_name: String = ""
const SUMMON_MIX_EXP_GAIN: int = 10

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	summon_mix_item.gui_input.connect(_on_summon_mix_item_gui_input)
	_refresh_exp_bar()

func init_scene(params: Dictionary) -> void:
	_summon_id = str(params.get("summon_id", "")).strip_edges()
	_summon_name = str(params.get("summon_name", "")).strip_edges()
	if is_node_ready():
		_refresh_exp_bar()

func _refresh_exp_bar() -> void:
	if _summon_id == "":
		summon_mix_bar_lv.text = "Lv. -"
		summon_mix_bar_exp.text = "0 / 0"
		return

	var progression: Dictionary = DataManager.get_esper_progression(_summon_id)
	var rank: int = maxi(1, int(progression.get("rank", 1)))
	var total_xp: int = maxi(0, int(progression.get("xp", 0)))

	var thresholds: Array[int] = _get_esper_exp_thresholds(rank)
	if thresholds.is_empty():
		var fallback_level: int = maxi(1, int(progression.get("level", 1)))
		summon_mix_bar_lv.text = "Lv. %d" % fallback_level
		summon_mix_bar_exp.text = "%d / 0" % total_xp
		return

	total_xp = mini(total_xp, thresholds[thresholds.size() - 1])
	var level: int = _calculate_level_from_xp(total_xp, thresholds)
	var level_index: int = level - 1
	var max_level_index: int = thresholds.size() - 1

	if level_index >= max_level_index:
		var cap_floor: int = 0
		if max_level_index > 0:
			cap_floor = thresholds[max_level_index - 1]
		var cap_required: int = maxi(1, thresholds[max_level_index] - cap_floor)
		summon_mix_bar_lv.text = "Lv. %d" % level
		summon_mix_bar_exp.text = "%d / %d" % [cap_required, cap_required]
		return

	var current_floor: int = thresholds[level_index]
	var next_total: int = thresholds[level_index + 1]
	var progress: int = maxi(0, total_xp - current_floor)
	var required: int = maxi(1, next_total - current_floor)

	summon_mix_bar_lv.text = "Lv. %d" % level
	summon_mix_bar_exp.text = "%d / %d" % [progress, required]

func _on_summon_mix_item_gui_input(event: InputEvent) -> void:
	if _summon_id == "":
		return
	if not (event is InputEventMouseButton):
		return

	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	var progression: Dictionary = DataManager.get_esper_progression(_summon_id)
	var rank: int = maxi(1, int(progression.get("rank", 1)))
	var total_xp: int = maxi(0, int(progression.get("xp", 0)))

	var thresholds: Array[int] = _get_esper_exp_thresholds(rank)
	if thresholds.is_empty():
		return

	var max_total_xp: int = thresholds[thresholds.size() - 1]
	var new_total_xp: int = mini(total_xp + SUMMON_MIX_EXP_GAIN, max_total_xp)
	var new_level: int = _calculate_level_from_xp(new_total_xp, thresholds)

	DataManager.set_esper_progression(_summon_id, rank, new_level, new_total_xp)
	_refresh_exp_bar()

func _get_esper_exp_thresholds(rank: int) -> Array[int]:
	var summon_template: Dictionary = DataManager.game_data_summons.get(_summon_id, {})
	var entries_value: Variant = summon_template.get("entries", [])
	if not (entries_value is Array):
		return []

	var entries: Array = entries_value
	if entries.is_empty():
		return []

	var rank_index: int = clampi(rank - 1, 0, entries.size() - 1)
	var entry_value: Variant = entries[rank_index]
	if not (entry_value is Dictionary):
		return []

	var entry: Dictionary = entry_value
	var exp_pattern_id: int = int(entry.get("exp_pattern", 0))
	if exp_pattern_id <= 0:
		return []

	var pattern_key: String = str(exp_pattern_id)
	var pattern_value: Variant = DataManager.game_data_summons_exp_patterns.get(pattern_key, DataManager.game_data_summons_exp_patterns.get(exp_pattern_id, []))
	if not (pattern_value is Array):
		return []

	var thresholds: Array[int] = _coerce_int_array(pattern_value)
	if thresholds.is_empty():
		return []
	if thresholds[0] > 0:
		thresholds.push_front(0)

	for i in range(1, thresholds.size()):
		thresholds[i] = maxi(thresholds[i], thresholds[i - 1])

	return thresholds

func _coerce_int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(maxi(0, int(value)))
	return result

func _calculate_level_from_xp(total_xp: int, thresholds: Array[int]) -> int:
	if thresholds.is_empty():
		return 1

	var safe_total_xp: int = maxi(0, total_xp)
	var level: int = 1
	for i in range(1, thresholds.size()):
		if safe_total_xp >= thresholds[i]:
			level = i + 1
		else:
			break
	return level

func _on_back_pressed() -> void:
	UIManager.pop()
