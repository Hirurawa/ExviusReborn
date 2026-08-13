extends Control
class_name MissionResultSequence

signal finished

const ITEM_ICON_DIR := "res://assets/items/"

## Beat before a gauge starts moving, so the player sees the pre-mission fill.
const EXP_FILL_DELAY := 0.35
const EXP_FILL_DURATION := 1.1

@onready var general: VBoxContainer = $General
@onready var mission_name: Label = $General/Locationnamebg/MissionName
@onready var gil: Label = $General/ResultBg/VBoxContainer/ResultNameBg/GilLabel
@onready var general_unit_exp: Label = $General/ResultBg/VBoxContainer/ResultNameBg2/UnitExpLabel
@onready var rank_exp: Label = $General/ResultBg/VBoxContainer/ResultNameBg3/RankExpLabel
@onready var rank_exp_gauge: TextureProgressBar = $"General/ResultBg/VBoxContainer/ResultExpBg/ResultExpBar"
@onready var rank_exp_label: Label = $"General/ResultBg/VBoxContainer/ResultRankupInfo/Label"

const UNIT_SCENE: PackedScene = preload("res://features/shared/Unit.tscn")

@onready var unit: VBoxContainer = $Unit
@onready var unit_unit_exp: Label = $Unit/ResultSubtitleLong/Label

@onready var unit_container: VBoxContainer = $Unit/ResultBg/VBoxContainer
@onready var unit_panel: TextureRect = $Unit/ResultBg/VBoxContainer/ResultUnit

@onready var item: VBoxContainer = $Items
@onready var item_container: VBoxContainer = $Items/ResultBg/VBoxContainer
@onready var item_panel: HBoxContainer = $Items/ResultBg/VBoxContainer/ItemRow

@onready var challenges: VBoxContainer = $Challenges
@onready var challenge_containter: VBoxContainer = $Challenges/ResultBg/VBoxContainer
const CHALLENGE_ROW := preload("res://features/outgame/map/DungeonMissionChallengeRow.tscn")

@onready var next_button: TextureButton = $NextButton

var _result: Dictionary
var _party: Array
var _stage: int

var _rank_tween: Tween
var _rank_before: int
var _xp_before: int
var _rank_after: int
var _xp_after: int
var _xp_gain: int
## Rank the gauge is currently drawing, so a mid-fill rank up can be spotted.
var _displayed_rank: int

var _unit_tween: Tween
var _unit_exp_gain: int
## One entry per party panel whose unit actually gains EXP, so a single tween can
## fill every unit's gauge in step. See _register_unit_exp_row for the shape.
var _unit_exp_rows: Array[Dictionary] = []

func _ready() -> void:
	next_button.pressed.connect(_on_next_pressed)

func start(result: Dictionary, party: Array) -> void:
	_result = result
	_party = party
	_show_summary()

func _show_summary() -> void:
	_stage = 0
	mission_name.text = str(_result.get("mission_name", "Mission Complete"))
	gil.text = str(_result.get("gil"))
	general_unit_exp.text = str(_result.get("unit_exp"))
	_start_rank_exp_animation()

## MissionService has already banked the rank EXP by the time we get here, so the
## gauge rewinds to the pre-mission XP and replays the award: RankExpLabel counts
## the earned EXP down to zero while the gauge fills. A rank gained mid-award
## wraps the gauge back to empty against the new rank's threshold.
func _start_rank_exp_animation() -> void:
	_rank_before = int(_result.get("rank_before", PlayerProfile.current_rank))
	_xp_before = int(_result.get("xp_before", PlayerProfile.current_xp))
	_rank_after = int(_result.get("rank_after", PlayerProfile.current_rank))
	_xp_after = int(_result.get("xp_after", PlayerProfile.current_xp))
	_xp_gain = maxi(0, int(_result.get("rank_exp", 0)))
	_displayed_rank = _rank_before

	# Early ranks need as little as 20 XP, so Range's default step of 1 would
	# make the fill jump in visible chunks. Disable snapping.
	rank_exp_gauge.step = 0.0
	_draw_rank_progress(0.0)

	if _rank_tween and _rank_tween.is_valid():
		_rank_tween.kill()
	if _xp_gain <= 0:
		return

	_rank_tween = create_tween()
	_rank_tween.tween_interval(EXP_FILL_DELAY)
	_rank_tween.tween_method(_draw_rank_progress, 0.0, float(_xp_gain), EXP_FILL_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_rank_tween.tween_callback(_show_final_rank_progress)

## Places the gauge and both labels at `gained` EXP into the award, walking the
## rank thresholds so the fill spans however many ranks the mission covered.
func _draw_rank_progress(gained: float) -> void:
	var rank: int = _rank_before
	var xp: float = float(_xp_before) + gained
	var threshold: float = _rank_threshold(rank)
	while rank < _rank_after and xp >= threshold:
		xp -= threshold
		rank += 1
		threshold = _rank_threshold(rank)
	xp = clampf(xp, 0.0, threshold)

	if rank != _displayed_rank:
		_displayed_rank = rank
		_flash_gauge(rank_exp_gauge)

	rank_exp_gauge.max_value = threshold
	rank_exp_gauge.value = xp
	rank_exp.text = "%d" % int(ceil(float(_xp_gain) - gained))
	rank_exp_label.text = "%d" % int(ceil(threshold - xp))

## Snaps to the values MissionService actually banked, so float drift in the
## tween can never leave the gauge a point short of the real total.
func _show_final_rank_progress() -> void:
	_displayed_rank = _rank_after
	var threshold: float = _rank_threshold(_rank_after)
	rank_exp_gauge.max_value = threshold
	rank_exp_gauge.value = clampf(float(_xp_after), 0.0, threshold)
	rank_exp.text = "0"
	rank_exp_label.text = "%d" % maxi(0, int(threshold) - _xp_after)

## Cuts the fill short when the player taps Next mid-animation. Returns whether
## there was an animation to skip.
func _skip_rank_exp_animation() -> bool:
	if _rank_tween == null or not _rank_tween.is_valid():
		return false
	_rank_tween.kill()
	_rank_tween = null
	_show_final_rank_progress()
	return true

## Brief brightness pulse marking the moment a gauge wraps into a new rank/level.
## A big EXP award can cross a level every few frames, so the previous pulse is
## killed rather than left to fight the new one over `modulate`; the gauge just
## stays lit until the last level lands.
func _flash_gauge(gauge: CanvasItem) -> void:
	if gauge.has_meta("flash_tween"):
		var running: Variant = gauge.get_meta("flash_tween")
		if running is Tween and running.is_valid():
			running.kill()

	var flash: Tween = create_tween()
	gauge.set_meta("flash_tween", flash)
	flash.tween_property(gauge, "modulate", Color(1.8, 1.8, 1.8), 0.08)
	flash.tween_property(gauge, "modulate", Color.WHITE, 0.25)

## XP needed to advance out of `rank`, matching PlayerProfile.add_xp's walk.
func _rank_threshold(rank: int) -> float:
	PlayerProfile.ensure_rank_exp_loaded()
	var rank_data: Dictionary = PlayerProfile.rank_exp_data
	if rank_data.has(rank):
		return float(rank_data[rank]["xp_needed"])
	if rank_data.is_empty():
		return float(maxi(1, PlayerProfile.next_rank_xp))
	return float(rank_data[rank_data.keys().max()]["xp_needed"])

func _show_experience() -> void:
	_stage = 1
	general.visible = false
	unit.visible = true
	challenges.visible = false
	item.visible = false
	_unit_exp_rows.clear()
	for party_unit in _party:
		_config_unit(party_unit)
	_start_unit_exp_animation()

## The unit panels open showing each unit where it stood before the mission, then
## every gauge fills at once while the header counts the awarded EXP down to zero.
func _start_unit_exp_animation() -> void:
	_unit_exp_gain = maxi(0, int(_result.get("unit_exp", 0)))
	_draw_unit_progress(0.0)

	if _unit_tween and _unit_tween.is_valid():
		_unit_tween.kill()
	if _unit_exp_gain <= 0:
		return

	_unit_tween = create_tween()
	_unit_tween.tween_interval(EXP_FILL_DELAY)
	_unit_tween.tween_method(_draw_unit_progress, 0.0, float(_unit_exp_gain), EXP_FILL_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_unit_tween.tween_callback(_show_final_unit_progress)

func _draw_unit_progress(gained: float) -> void:
	unit_unit_exp.text = "%d" % int(ceil(float(_unit_exp_gain) - gained))
	for row in _unit_exp_rows:
		_draw_unit_row(row, float(row["xp_before"]) + gained)

## Places one unit's gauge, level and next-EXP label at `xp` total EXP. Levels
## gained mid-fill wrap the gauge against the new level's span, mirroring how the
## rank gauge handles a rank up.
func _draw_unit_row(row: Dictionary, xp: float) -> void:
	var bar: TextureProgressBar = row["bar"]
	var progress: Dictionary = UnitService.level_progress_at_xp(row["unit"], int(xp))
	var level: int = int(progress.get("level", 1))
	if level != int(row["level"]):
		row["level"] = level
		_flash_gauge(bar)
	row["level_label"].text = str(level)

	if bool(progress.get("at_max_level", false)):
		bar.max_value = 1.0
		bar.value = 1.0
		row["next_exp_label"].text = "0"
		return

	var level_floor: float = float(progress.get("level_floor", 0))
	var span: float = maxf(1.0, float(progress.get("next_floor", 1)) - level_floor)
	var into_level: float = clampf(xp - level_floor, 0.0, span)
	bar.max_value = span
	bar.value = into_level
	row["next_exp_label"].text = "%d" % int(ceil(span - into_level))

## Snaps every gauge to the EXP UnitService actually banked, so tween float drift
## can't leave a unit a point short of its real total.
func _show_final_unit_progress() -> void:
	unit_unit_exp.text = "0"
	for row in _unit_exp_rows:
		_draw_unit_row(row, float(row["xp_after"]))

## Cuts the fill short when the player taps Next mid-animation. Returns whether
## there was an animation to skip.
func _skip_unit_exp_animation() -> bool:
	if _unit_tween == null or not _unit_tween.is_valid():
		return false
	_unit_tween.kill()
	_unit_tween = null
	_show_final_unit_progress()
	return true

## Draws the panel's gauge at the unit's pre-mission EXP and, when the mission
## actually moved it, registers the panel for the shared fill tween. Units that
## earned nothing -- and units already at max level -- are drawn once and sit the
## animation out.
func _register_unit_exp_row(unit_data: Dictionary, instance_id: String, bar: TextureProgressBar, level_label: Label, next_exp_label: Label) -> void:
	var award: Dictionary = _exp_award_for(instance_id)
	var xp_after: int = int(award.get("xp_after", unit_data.get("xp", 0)))
	var xp_before: int = int(award.get("xp_before", xp_after))
	var start: Dictionary = UnitService.level_progress_at_xp(unit_data, xp_before)

	# Early levels span as little as a handful of EXP, so Range's default step of
	# 1 would make the fill jump in visible chunks. Disable snapping.
	bar.step = 0.0
	var row: Dictionary = {
		"unit": unit_data,
		"bar": bar,
		"level_label": level_label,
		"next_exp_label": next_exp_label,
		"xp_before": xp_before,
		"xp_after": xp_after,
		"level": int(start.get("level", 1)),
	}
	_draw_unit_row(row, float(xp_before))

	if xp_after > xp_before and not bool(start.get("at_max_level", false)):
		_unit_exp_rows.append(row)

## The mission's EXP award for a party member, or {} when the unit earned none
## (UnitService.award_battle_exp skips material units).
func _exp_award_for(instance_id: String) -> Dictionary:
	if instance_id == "":
		return {}
	for award in _result.get("unit_exp_awards", []):
		if str(award.get("instance_id", "")) == instance_id:
			return award
	return {}

func _config_unit(party_unit: Dictionary) -> void:
	if party_unit == {}:
		var placeholder: TextureRect = TextureRect.new()
		placeholder.texture = ResourceLoader.load("res://assets/ui/quest/result_unit.tres") as Texture2D
		placeholder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		placeholder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		placeholder.custom_minimum_size = Vector2(640, 180)
		unit_container.add_child(placeholder)
		return

	# Show the roster entry when the mission's EXP levelled this unit up, so the
	# level and the stat block on the results screen agree.
	var unit_data: Dictionary = _post_battle_unit(party_unit)

	var unit_node = unit_panel.duplicate()
	unit_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	unit_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	unit_node.custom_minimum_size = Vector2(640, 180)
	var hp_text = unit_node.get_node("VBoxContainer/HBoxContainer/HPLabel")
	hp_text.text = str(unit_data.get("final_stats").get("stats").get("HP"))
	var atk_text = unit_node.get_node("VBoxContainer/HBoxContainer/ATKLabel")
	atk_text.text = str(unit_data.get("final_stats").get("stats").get("ATK"))
	var mag_text = unit_node.get_node("VBoxContainer/HBoxContainer/MAGLabel")
	mag_text.text = str(unit_data.get("final_stats").get("stats").get("MAG"))
	var mp_text = unit_node.get_node("VBoxContainer/HBoxContainer2/MPLabel")
	mp_text.text = str(unit_data.get("final_stats").get("stats").get("MP"))
	var def_text = unit_node.get_node("VBoxContainer/HBoxContainer2/DEFLabel")
	def_text.text = str(unit_data.get("final_stats").get("stats").get("DEF"))
	var spr_text = unit_node.get_node("VBoxContainer/HBoxContainer2/SPRLabel")
	spr_text.text = str(unit_data.get("final_stats").get("stats").get("SPR"))
	var lvl_text = unit_node.get_node("UnitStatusLabelLv/UnitLevel")
	lvl_text.text = str(unit_data.get("level"))
	var lb_lvl_text = unit_node.get_node("UnitStatusLabelLv2/LBLevel")
	lb_lvl_text.text = str(int(unit_data.get("limitburst_level")))
	var lb_name_text = unit_node.get_node("LBName")
	var lb_id: String = str(unit_data.get("limitBurstId", ""))
	var lb_data: Dictionary = GameDatabase.get_limitburst(lb_id) if (lb_id != "" and lb_id != "<null>") else {}
	if not lb_data.is_empty():
		var lb_name: String = str(lb_data.get("name", "Unknown Limit Burst"))
		lb_name_text.text = lb_name
	else:
		lb_name_text.text = str(unit_data.get("limitBurstId"))
	var tm_value_text = unit_node.get_node("UnitBondsIconMini/TMValue")
	tm_value_text.text = str(unit_data.get("trust_value"))
	var job_name_text = unit_node.get_node("UnitCharaLabelJob/JobName")
	job_name_text.text = GameDatabase.get_job_name(unit_data.get("jobId"))
	var unit_name_text = unit_node.get_node("UnitName")
	unit_name_text.text = str(unit_data.get("unitName"))
	
	# The level and next-EXP labels are driven by the fill animation from here on,
	# so they start at the unit's pre-mission state rather than its final one.
	var unit_next_exp: Label = unit_node.get_node("UnitLvupInfo2/NextExpLabel")
	var exp_bar: TextureProgressBar = unit_node.get_node("UnitExpBg/UnitExpBar")
	_register_unit_exp_row(unit_data, str(party_unit.get("instance_id", "")), exp_bar, lvl_text, unit_next_exp)

	var unit_texture = unit_node.get_node("UnitTexture")
	var unit_visual: Control = UNIT_SCENE.instantiate() as Control
	if unit_visual:
		unit_visual.scene_size = "small"
		unit_visual.unit_data_to_load = unit_data
		unit_visual.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		unit_texture.add_child(unit_visual)
	
	unit_node.visible = true
	unit_container.add_child(unit_node)

## The party dicts are the pre-battle snapshot, so a unit that gained a level from
## the mission's combat EXP would show its old level and stats. When the unit is in
## the award list, display its refreshed roster entry instead.
func _post_battle_unit(unit_data: Dictionary) -> Dictionary:
	var instance_id: String = str(unit_data.get("instance_id", ""))
	if instance_id == "":
		return unit_data

	var award: Dictionary = _exp_award_for(instance_id)
	if int(award.get("level_after", 0)) <= int(award.get("level_before", 0)):
		return unit_data

	for owned_unit in UnitService.owned_units_ids:
		if owned_unit is Dictionary and str(owned_unit.get("instance_id", "")) == instance_id:
			return owned_unit
	return unit_data

func _show_item() -> void:
	_stage = 2
	var drops = _result.get("drops", [])
	if drops == []:
		_show_mission_results()
		return
	general.visible = false
	unit.visible = false
	item.visible = true
	challenges.visible = false
	for dropped_item in drops:
		_config_item(dropped_item)

func _config_item(item_id: String) -> void:
	var item_node = item_panel.duplicate()
	var item_data = GameDatabase.get_item(int(item_id))
	var item_texture = item_node.get_node("ItemFrame1/ItemTexture")
	item_texture.texture = ResourceLoader.load(ITEM_ICON_DIR + item_data.get("iconFile")) as Texture2D
	var item_name = item_node.get_node("ItemName")
	item_name.text = str(item_data.get("name"))
	item_node.visible = true
	item_container.add_child(item_node)

func _show_mission_results() -> void:
	_stage = 3
	general.visible = false
	unit.visible = false
	item.visible = false
	challenges.visible = true
	var challenge_data = _result.get("challenges", [])
	for i in range(challenge_data.size()):
		_config_challenge(challenge_data[i], _result.get("objectives")[i])

func _config_challenge(challenge: Dictionary, objective: bool) -> void:
	var row = CHALLENGE_ROW.instantiate()
	challenge_containter.add_child(row)
	row.configure(challenge.get("string"), challenge.get("reward"), objective)

func _on_next_pressed() -> void:
	# First tap during a fill fast-forwards the gauges instead of advancing.
	if _stage == 0 and _skip_rank_exp_animation():
		return
	if _stage == 1 and _skip_unit_exp_animation():
		return
	match _stage:
		0:
			_show_experience()
		1:
			_show_item()
		2:
			_show_mission_results()
		_:
			finished.emit()
