extends Control
class_name MissionResultSequence

signal finished

const ITEM_ICON_DIR := "res://assets/items/"

@onready var general: VBoxContainer = $General
@onready var mission_name: Label = $General/Locationnamebg/MissionName
@onready var gil: Label = $General/ResultBg/VBoxContainer/ResultNameBg/GilLabel
@onready var general_unit_exp: Label = $General/ResultBg/VBoxContainer/ResultNameBg2/UnitExpLabel
@onready var rank_exp: Label = $General/ResultBg/VBoxContainer/ResultNameBg3/RankExpLabel

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
	rank_exp.text = str(_result.get("rank_exp"))

func _show_experience() -> void:
	_stage = 1
	general.visible = false
	unit.visible = true
	challenges.visible = false
	item.visible = false
	unit_unit_exp.text = str(_result.get("unit_exp"))
	for party_unit in _party:
		_config_unit(party_unit)

func _config_unit(unit_data: Dictionary) -> void:
	if unit_data == {}:
		var placeholder: TextureRect = TextureRect.new()
		placeholder.texture = ResourceLoader.load("res://assets/ui/quest/result_unit.tres") as Texture2D
		unit_container.add_child(placeholder)
		return
	
	var unit_node = unit_panel.duplicate()
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
	lb_name_text.text = str(unit_data.get("limitBurstId"))
	var tm_value_text = unit_node.get_node("UnitBondsIconMini/TMValue")
	tm_value_text.text = str(unit_data.get("trust_value"))
	var job_name_text = unit_node.get_node("UnitCharaLabelJob/JobName")
	job_name_text.text = str(unit_data.get("jobId"))
	var unit_name_text = unit_node.get_node("UnitName")
	unit_name_text.text = str(unit_data.get("unitName"))
	unit_node.visible = true
	unit_container.add_child(unit_node)

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
	row.configure(challenge.get("string"), challenge.get("reward")[2], objective)

func _on_next_pressed() -> void:
	match _stage:
		0:
			_show_experience()
		1:
			_show_item()
		2:
			_show_mission_results()
		_:
			finished.emit()
