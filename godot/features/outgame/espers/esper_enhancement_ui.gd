extends Control

@onready var back_button: TextureButton = $UnitNamebgChara2/BackButton
@onready var summon_mix_item: Control = $summon_mix_item
@onready var summon_mix_bar_lv: Label = $summon_mix_bar_area/summon_mix_bar_lv
@onready var summon_mix_bar_exp: Label = $summon_mix_bar_area/summon_mix_bar_exp
@onready var cp_label: Label = $cp_area/label_cp
@onready var xp_bar: TextureRect = $summon_mix_bar_area/summon_mix_bar_frame/summon_mix_bar
@onready var summon_image: TextureRect = $SummonImage

var _summon_id: String = ""
var _summon_name: String = ""
const SUMMON_MIX_EXP_GAIN: int = 1000
const SUMMON_MIX_HOLD_INITIAL_DELAY: float = 0.35
const SUMMON_MIX_HOLD_REPEAT_INTERVAL: float = 0.08

var _is_summon_mix_held: bool = false
var _summon_mix_hold_elapsed: float = 0.0
var _summon_mix_next_repeat_at: float = 0.0

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	summon_mix_item.gui_input.connect(_on_summon_mix_item_gui_input)
	set_process(true)
	_refresh_exp_bar()

func _process(delta: float) -> void:
	if not _is_summon_mix_held:
		return
	if _summon_id == "":
		_stop_summon_mix_hold()
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_stop_summon_mix_hold()
		return

	_summon_mix_hold_elapsed += delta
	while _summon_mix_hold_elapsed >= _summon_mix_next_repeat_at:
		if not _add_summon_mix_xp():
			_stop_summon_mix_hold()
			return
		_summon_mix_next_repeat_at += SUMMON_MIX_HOLD_REPEAT_INTERVAL

func init_scene(params: Dictionary) -> void:
	_summon_id = str(params.get("summon_id", "")).strip_edges()
	_summon_name = str(params.get("summon_name", "")).strip_edges()
	summon_image.texture = _get_summon_image_texture(_summon_id)
	if is_node_ready():
		_refresh_exp_bar()

func _refresh_exp_bar() -> void:
	if _summon_id == "":
		summon_mix_bar_lv.text = "Lv. -"
		summon_mix_bar_exp.text = "0 / 0"
		cp_label.text = "0"
		return

	var progression: Dictionary = EsperService.get_esper_progression(_summon_id)
	var current_sp: int = maxi(0, int(progression.get("current_sp", 0)))
	cp_label.text = str(current_sp)
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

	var fill_ratio: float = clampf(float(progress) / float(required), 0.0, 1.0)
	xp_bar.scale.x = fill_ratio

func _on_summon_mix_item_gui_input(event: InputEvent) -> void:
	if _summon_id == "":
		return
	if not (event is InputEventMouseButton):
		return

	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	if not mouse_button.pressed:
		_stop_summon_mix_hold()
		return

	_is_summon_mix_held = true
	_summon_mix_hold_elapsed = 0.0
	_summon_mix_next_repeat_at = SUMMON_MIX_HOLD_INITIAL_DELAY
	if not _add_summon_mix_xp():
		_stop_summon_mix_hold()


func _add_summon_mix_xp() -> bool:
	var progression: Dictionary = EsperService.get_esper_progression(_summon_id)
	var rank: int = maxi(1, int(progression.get("rank", 1)))
	var total_xp: int = maxi(0, int(progression.get("xp", 0)))

	var thresholds: Array[int] = _get_esper_exp_thresholds(rank)
	if thresholds.is_empty():
		return false

	var max_total_xp: int = thresholds[thresholds.size() - 1]
	if total_xp >= max_total_xp:
		return false

	var new_total_xp: int = mini(total_xp + SUMMON_MIX_EXP_GAIN, max_total_xp)
	var new_level: int = _calculate_level_from_xp(new_total_xp, thresholds)
	var old_level: int = _calculate_level_from_xp(total_xp, thresholds)

	EsperService.set_esper_progression(_summon_id, rank, new_level, new_total_xp, old_level)
	_refresh_exp_bar()
	return new_total_xp < max_total_xp

func _get_esper_exp_thresholds(rank: int) -> Array[int]:
	var summon_template: Dictionary = GameDatabase.get_esper(int(_summon_id), rank)
	
	var exp_pattern_id: int = int(summon_template.get("expPatternId", 0))
	if exp_pattern_id <= 0:
		return []

	var pattern_value: Variant = GameDatabase.get_esper_exp_pattern(exp_pattern_id)
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
		result.append(maxi(0, int(value.get("needExp"))))
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

func _get_summon_image_texture(summon_id: String) -> Texture2D:
	if summon_id == "":
		return null

	var summon_data: Dictionary = GameDatabase.get_esper(int(summon_id))
	if summon_data.is_empty():
		return null

	var image_filename: String = str(summon_data.get("beastImage", "")).strip_edges()
	if image_filename == "":
		return null

	var image_path: String = "res://assets/esper/" + image_filename
	if not ResourceLoader.exists(image_path):
		return null

	return ResourceLoader.load(image_path) as Texture2D

func _on_back_pressed() -> void:
	_stop_summon_mix_hold()
	UIManager.pop()

func _exit_tree() -> void:
	_stop_summon_mix_hold()

func _stop_summon_mix_hold() -> void:
	_is_summon_mix_held = false
	_summon_mix_hold_elapsed = 0.0
	_summon_mix_next_repeat_at = 0.0
