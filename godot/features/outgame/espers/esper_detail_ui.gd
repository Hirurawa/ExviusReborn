extends Control

@onready var back_button: TextureButton = $UnitNamebgChara2/BackButton
@onready var board_button: TextureButton = $btn_board
@onready var powerup_button: TextureButton = $btn_powerup
@onready var reset_button: TextureButton = $btn_reset
@onready var title_label: Label = $UnitNamebgChara2/Title
@onready var summon_image: TextureRect = $SummonImage
@onready var level_label: Label = $lv_label
@onready var hp_label: Label = $status_frame/label_hp
@onready var mp_label: Label = $status_frame/label_mp
@onready var atk_label: Label = $status_frame/label_atk
@onready var def_label: Label = $status_frame/label_def
@onready var mag_label: Label = $status_frame/label_int
@onready var mind_label: Label = $status_frame/label_mind
@onready var cp_label: Label = $label_cp
@onready var skill_name: Label = $skill_name_label
@onready var skill_desc: Label = $skill_desc_label

var _summon_id: String = ""
var _summon_name: String = ""

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	board_button.pressed.connect(_on_board_pressed)
	powerup_button.pressed.connect(_on_powerup_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	var updated_callable: Callable = Callable(self, "_on_espers_updated")
	if not EsperService.espers_updated.is_connected(updated_callable):
		EsperService.espers_updated.connect(updated_callable)
	_refresh_ui()

func _exit_tree() -> void:
	var updated_callable: Callable = Callable(self, "_on_espers_updated")
	if EsperService.espers_updated.is_connected(updated_callable):
		EsperService.espers_updated.disconnect(updated_callable)

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

	var progression: Dictionary = EsperService.get_esper_progression(_summon_id)
	var rank: int = maxi(1, int(progression.get("rank", 1)))
	var level: int = maxi(1, int(progression.get("level", 1)))
	var current_sp: int = maxi(0, int(progression.get("current_sp", 0)))
	skill_name.text = ""
	skill_desc.text = ""
	level_label.text = "Lv. %d (R%d)" % [level, rank]
	cp_label.text = str(current_sp)

	var summon_data: Dictionary = StaticData.game_data_summons.get(_summon_id, {})
	summon_image.texture = _get_summon_image_texture(summon_data)
	var resolved_skill: Dictionary = _resolve_rank_skill_data(summon_data, rank)
	if not resolved_skill.is_empty():
		skill_name.text = _get_skill_text_by_key(resolved_skill, "name")
		skill_desc.text = _get_skill_text_by_key(resolved_skill, "desc")

	var stats: Dictionary = _extract_stats_for_level_and_rank(summon_data, rank, level)
	var board_stat_bonus: Dictionary = EsperService.get_esper_board_stat_bonuses(_summon_id)
	for stat_key in ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]:
		stats[stat_key] = int(stats.get(stat_key, 0)) + int(board_stat_bonus.get(stat_key, 0))
	hp_label.text = str(stats.get("HP", 0))
	mp_label.text = str(stats.get("MP", 0))
	atk_label.text = str(stats.get("ATK", 0))
	def_label.text = str(stats.get("DEF", 0))
	mag_label.text = str(stats.get("MAG", 0))
	mind_label.text = str(stats.get("SPR", 0))

func _resolve_rank_max_level(entry: Dictionary) -> int:
	var cp_pattern_value: Variant = entry.get("cp_pattern", [])
	if cp_pattern_value is Array:
		var cp_pattern: Array = cp_pattern_value
		if not cp_pattern.is_empty():
			return maxi(1, cp_pattern.size())
	return 1

func _interpolate_stat_value(value: Variant, level: int, rank_max_level: int) -> int:
	if value is Array:
		var values: Array = value
		if values.is_empty():
			return 0
		if values.size() == 1:
			return int(values[0])

		var min_value: float = float(values[0])
		var max_value: float = float(values[1])
		var clamped_max_level: int = maxi(1, rank_max_level)
		var clamped_level: int = clampi(level, 1, clamped_max_level)
		if clamped_max_level <= 1:
			return int(round(min_value))

		var interpolated: float = min_value + float(clamped_level - 1) * (max_value - min_value) / float(clamped_max_level - 1)
		return int(round(interpolated))

	return int(value)

func _extract_stats_for_level_and_rank(summon_data: Dictionary, rank: int, level: int) -> Dictionary:
	var entries_value: Variant = summon_data.get("entries", [])
	if not (entries_value is Array):
		return {}

	var entries: Array = entries_value
	if entries.is_empty():
		return {}

	var clamped_rank_index: int = clampi(rank - 1, 0, entries.size() - 1)
	var selected_entry: Variant = entries[clamped_rank_index]
	if not (selected_entry is Dictionary):
		return {}
	var entry_data: Dictionary = selected_entry
	var rank_max_level: int = _resolve_rank_max_level(entry_data)

	var stats_value: Variant = entry_data.get("stats", {})
	if not (stats_value is Dictionary):
		return {}

	var raw_stats: Dictionary = stats_value
	var resolved_stats: Dictionary = {}
	for stat_key in ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]:
		resolved_stats[stat_key] = _interpolate_stat_value(raw_stats.get(stat_key, 0), level, rank_max_level)
	return resolved_stats

func _get_summon_image_texture(summon_data: Dictionary) -> Texture2D:
	if summon_data.is_empty():
		return null

	var image_filename: String = str(summon_data.get("image", "")).strip_edges()
	if image_filename == "":
		return null

	var image_path: String = "res://assets/esper/" + image_filename
	if not ResourceLoader.exists(image_path):
		return null

	return ResourceLoader.load(image_path) as Texture2D

func _resolve_rank_skill_data(summon_data: Dictionary, rank: int) -> Dictionary:
	var skill_value: Variant = summon_data.get("skill", {})
	if not (skill_value is Dictionary):
		return {}

	var skill_data: Dictionary = skill_value
	if skill_data.is_empty():
		return {}

	var summon_numeric_id: int = int(_summon_id)
	var expected_skill_id: String = "%d%02d" % [100 + summon_numeric_id, rank]
	var direct_match: Variant = skill_data.get(expected_skill_id, {})
	if direct_match is Dictionary:
		var direct_dict: Dictionary = direct_match
		if not direct_dict.is_empty():
			return direct_dict

	# Fallback: prefer any key whose last digit matches the current rank.
	for key_value in skill_data.keys():
		var key: String = str(key_value)
		if key.ends_with(str(rank)):
			var rank_match: Variant = skill_data.get(key, {})
			if rank_match is Dictionary:
				var rank_dict: Dictionary = rank_match
				if not rank_dict.is_empty():
					return rank_dict

	return {}

func _get_skill_text_by_key(skill_data: Dictionary, text_key: String) -> String:
	var strings_value: Variant = skill_data.get("strings", {})
	if not (strings_value is Dictionary):
		return ""

	var strings: Dictionary = strings_value
	var text_value: Variant = strings.get(text_key, [])
	if not (text_value is Array):
		return ""

	var localized_values: Array = text_value
	if localized_values.is_empty():
		return ""

	return str(localized_values[0])

func _on_espers_updated(_espers: Array) -> void:
	if _summon_id == "":
		return
	_refresh_ui()

func _on_back_pressed() -> void:
	UIManager.pop()

func _on_board_pressed() -> void:
	UIManager.push("summon_board_ui", {
		"summon_id": _summon_id,
		"summon_name": _summon_name
	})
	
func _on_powerup_pressed() -> void:
	UIManager.push("esper_enhancement_ui", {
		"summon_id": _summon_id,
		"summon_name": _summon_name
	})

func _on_reset_pressed() -> void:
	if _summon_id == "":
		return

	var result: Dictionary = EsperService.reset_esper_board_progression(_summon_id)
	if not bool(result.get("success", false)):
		return

	_refresh_ui()
