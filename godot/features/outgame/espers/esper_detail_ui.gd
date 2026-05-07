extends Control

@onready var back_button: TextureButton = $UnitNamebgChara2/BackButton
@onready var board_button: TextureButton = $btn_board
@onready var title_label: Label = $UnitNamebgChara2/Title
@onready var summon_name_bg: TextureRect = $summon_mix_name_bg
@onready var summon_name_label: Label = $summon_mix_name_label
@onready var level_label: Label = $lv_label
@onready var hp_label: Label = $status_frame/label_hp
@onready var mp_label: Label = $status_frame/label_mp
@onready var atk_label: Label = $status_frame/label_atk
@onready var def_label: Label = $status_frame/label_def
@onready var mag_label: Label = $status_frame/label_int
@onready var mind_label: Label = $status_frame/label_mind

var _summon_id: String = ""
var _summon_name: String = ""

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	board_button.pressed.connect(_on_board_pressed)
	_refresh_ui()

func init_scene(params: Dictionary) -> void:
	_summon_id = str(params.get("summon_id", "")).strip_edges()
	_summon_name = str(params.get("summon_name", "")).strip_edges()
	if is_node_ready():
		_refresh_ui()

func _refresh_ui() -> void:
	var display_name: String = _summon_name
	if display_name == "" and _summon_id != "":
		display_name = "Summon %s" % _summon_id
	if display_name == "":
		display_name = "Esper"

	title_label.text = display_name
	summon_name_bg.visible = true
	summon_name_label.visible = true
	summon_name_label.text = display_name
	level_label.text = "Lv. 1"

	var summon_data: Dictionary = DataManager.game_data_summons.get(_summon_id, {})
	var stats: Dictionary = _extract_stats(summon_data)
	hp_label.text = str(stats.get("HP", 0))
	mp_label.text = str(stats.get("MP", 0))
	atk_label.text = str(stats.get("ATK", 0))
	def_label.text = str(stats.get("DEF", 0))
	mag_label.text = str(stats.get("MAG", 0))
	mind_label.text = str(stats.get("MND", 0))

func _extract_stats(summon_data: Dictionary) -> Dictionary:
	var entries_value: Variant = summon_data.get("entries", [])
	if not (entries_value is Array):
		return {}

	var entries: Array = entries_value
	if entries.is_empty():
		return {}

	var first_entry: Variant = entries[0]
	if not (first_entry is Dictionary):
		return {}

	var stats_value: Variant = first_entry.get("stats", {})
	if not (stats_value is Dictionary):
		return {}

	var raw_stats: Dictionary = stats_value
	var resolved_stats: Dictionary = {}
	for stat_key in ["HP", "MP", "ATK", "DEF", "MAG", "MND"]:
		resolved_stats[stat_key] = _extract_stat_value(raw_stats.get(stat_key, 0))
	return resolved_stats

func _extract_stat_value(value: Variant) -> int:
	if value is Array:
		var values: Array = value
		if values.is_empty():
			return 0
		return int(values[0])
	return int(value)

func _on_back_pressed() -> void:
	UIManager.pop()

func _on_board_pressed() -> void:
	UIManager.push("summon_board_ui", {
		"summon_id": _summon_id,
		"summon_name": _summon_name
	})
