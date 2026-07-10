extends Control
class_name MissionResultSequence

signal finished

const EMPTY_STAR := preload("res://assets/ui/quest/quest_missionstar_silver.tres")
const FILLED_STAR := preload("res://assets/ui/quest/quest_missionstar.tres")
const COMPLETE_TEXTURE := preload("res://assets/ui/quest/quest_mission_complete.tres")
const EXP_BG := preload("res://assets/ui/quest/result_exp_bg.tres")
const EXP_BAR := preload("res://assets/ui/quest/result_exp_bar.tres")
const ITEM_ICON_DIR := "res://assets/items/"

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var details: VBoxContainer = %Details
@onready var next_button: Button = %NextButton

var _result: Dictionary
var _party: Array
var _stage: int

func _ready() -> void:
	next_button.pressed.connect(_on_next_pressed)

func start(result: Dictionary, party: Array) -> void:
	_result = result
	_party = party
	_show_summary()

func _show_summary() -> void:
	_stage = 0
	title_label.text = "Results"
	subtitle_label.text = str(_result.get("mission_name", "Mission Complete"))
	_clear_details()
	_add_section("QUEST REWARDS")
	_add_value_row("Gil", "+%d" % int(_result.get("gil", 0)))
	_add_value_row("Unit EXP", "%d" % int(_result.get("unit_exp", _result.get("rank_exp", 0))))
	_add_value_row("Rank EXP", "%d" % int(_result.get("rank_exp", 0)))
	_add_section("OBTAINED ITEMS")
	_add_drop_rows(_result.get("drops", []))
	next_button.text = "Next"

func _show_experience() -> void:
	_stage = 1
	title_label.text = "Results"
	subtitle_label.text = "UNIT EXP                                      %d" % int(_result.get("unit_exp", _result.get("rank_exp", 0)))
	_clear_details()
	for unit in _party:
		if unit is Dictionary and not unit.is_empty():
			_add_unit_row(unit)
	next_button.text = "Next"

func _show_mission_results() -> void:
	_stage = 2
	title_label.text = "Results"
	subtitle_label.text = "Mission"
	_clear_details()
	_add_section("Initial Completion Reward")
	var challenges: Array = _result.get("challenges", [])
	var objectives: Array = _result.get("objectives", [])
	for index in range(challenges.size()):
		if index == 1:
			_add_section("Achievement Reward")
		var completed: bool = index < objectives.size() and bool(objectives[index])
		_add_challenge_row(str(challenges[index].get("string", "Challenge")), completed)
	next_button.text = "Next"
	_animate_completed_challenges()

func _add_section(text: String) -> void:
	var label := _new_label(text, 16, Color(0.72, 0.92, 1.0))
	label.custom_minimum_size.y = 30
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(label)

func _add_line(text: String, font_size: int, color: Color = Color.WHITE) -> void:
	var label := _new_label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, 42)
	details.add_child(label)

func _add_value_row(name: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 48
	var left := _new_label(name, 20)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := _new_label(value, 20, Color(0.65, 0.95, 1.0))
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(left)
	row.add_child(right)
	details.add_child(row)

func _add_unit_row(unit: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 116
	var box := VBoxContainer.new()
	var name := str(unit.get("unitName", unit.get("name", "Unit")))
	var header := HBoxContainer.new()
	var name_label := _new_label(name, 18)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var level_label := _new_label("Lv. %d" % int(unit.get("level", 1)), 18, Color(0.65, 0.95, 1.0))
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(name_label)
	header.add_child(level_label)
	box.add_child(header)
	var stats: Dictionary = _unit_stats(unit)
	box.add_child(_new_label("HP %d     MP %d     ATK %d     DEF %d     MAG %d     SPR %d" % [
		int(stats.get("HP", 0)), int(stats.get("MP", 0)), int(stats.get("ATK", 0)),
		int(stats.get("DEF", 0)), int(stats.get("MAG", 0)), int(stats.get("SPR", 0)),
	], 14, Color(0.7, 1.0, 0.7)))
	var gauge := TextureProgressBar.new()
	gauge.custom_minimum_size.y = 28
	gauge.texture_under = EXP_BG
	gauge.texture_progress = EXP_BAR
	gauge.value = 65
	box.add_child(gauge)
	panel.add_child(box)
	details.add_child(panel)

func _unit_stats(unit: Dictionary) -> Dictionary:
	var final_stats: Dictionary = unit.get("final_stats", {})
	var stats: Dictionary = final_stats.get("stats", {}) if final_stats is Dictionary else {}
	if not stats.is_empty():
		return stats
	return {
		"HP": int(unit.get("max_hp", unit.get("hp", unit.get("current_hp", 0)))),
		"MP": int(unit.get("max_mp", unit.get("mp", unit.get("current_mp", 0)))),
		"ATK": int(unit.get("atk", 0)),
		"DEF": int(unit.get("def", 0)),
		"MAG": int(unit.get("mag", 0)),
		"SPR": int(unit.get("spr", 0)),
	}

func _add_drop_rows(drops: Array) -> void:
	if drops.is_empty():
		_add_line("None", 18)
		return
	var counts: Dictionary = {}
	for drop_id in drops:
		var key: String = str(drop_id)
		counts[key] = int(counts.get(key, 0)) + 1
	for drop_id in counts.keys():
		_add_drop_row(str(drop_id), int(counts[drop_id]))

func _add_drop_row(drop_id: String, count: int) -> void:
	var item_data: Dictionary = GameDatabase.get_item(int(drop_id)) if drop_id.is_valid_int() else {}
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 56
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_file: String = str(item_data.get("iconFile", ""))
	if icon_file != "" and ResourceLoader.exists(ITEM_ICON_DIR + icon_file):
		icon.texture = load(ITEM_ICON_DIR + icon_file)
	row.add_child(icon)
	var name_text: String = str(item_data.get("name", drop_id))
	var name_label := _new_label(name_text, 18)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var count_label := _new_label("×%d" % count, 18, Color(0.65, 0.95, 1.0))
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(count_label)
	details.add_child(row)

func _add_challenge_row(text: String, completed: bool) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 78
	var star := TextureRect.new()
	star.name = "CompletedStar" if completed else "Star"
	star.custom_minimum_size = Vector2(66, 66)
	star.texture = EMPTY_STAR
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(star)
	var label := _new_label(text, 18)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var reward := _new_label("Lapis × 10", 15, Color(0.75, 0.9, 1.0))
	reward.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(reward)
	details.add_child(row)

func _animate_completed_challenges() -> void:
	next_button.disabled = true
	for star in details.find_children("CompletedStar", "TextureRect", true, false):
		star.texture = FILLED_STAR
		star.scale = Vector2(1.5, 1.5)
		star.pivot_offset = star.size / 2.0
		create_tween().tween_property(star, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK)
		await get_tree().create_timer(0.35).timeout
	var complete := TextureRect.new()
	complete.texture = COMPLETE_TEXTURE
	complete.custom_minimum_size = Vector2(304, 72)
	complete.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	complete.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	complete.modulate.a = 0.0
	details.add_child(complete)
	await create_tween().tween_property(complete, "modulate:a", 1.0, 0.2).finished
	next_button.disabled = false

func _new_label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	return label

func _clear_details() -> void:
	for child in details.get_children():
		child.free()

func _on_next_pressed() -> void:
	match _stage:
		0:
			_show_experience()
		1:
			_show_mission_results()
		_:
			finished.emit()
