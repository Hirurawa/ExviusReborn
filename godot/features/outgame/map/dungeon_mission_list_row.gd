extends Control
class_name DungeonMissionListRow

# Dumb UI: one mission row. configure() sets labels and badges; row_pressed fires on tap.

enum RowState { DEFAULT, ACHIEVING, CLEAR }

const PLATE_IDLE: Texture2D = preload("res://assets/ui/quest/quest_plate1.tres")
const PLATE_PRESSED: Texture2D = preload("res://assets/ui/quest/quest_plate2.tres")
const BADGE_NEW: Texture2D = preload("res://assets/ui/quest/quest_new.tres")
const BADGE_COMPLETE: Texture2D = preload("res://assets/ui/quest/quest_complete.tres")

const PLATE_SIZE: Vector2 = Vector2(640.0, 168.0)
const PLATE_TOP: float = 20.0
const BADGE_LEFT: float = 16.0
const BADGE_SPLIT_LINE_Y: float = 16.0
const BADGE_TOP_MARGIN: float = 20.0

signal row_pressed(mission_id: String)

@onready var plate_button: TextureButton = $PlateButton
@onready var status_badge: TextureRect = $StatusBadge
@onready var name_label: Label = $PlateButton/Overlay/NameLabel
@onready var energy_label: Label = $PlateButton/Overlay/StatsColumn/QuestStamina/EnergyLabel
@onready var battles_label: Label = $PlateButton/Overlay/StatsColumn/QuestWave/BattlesLabel
@onready var difficulty_label: Label = $PlateButton/Overlay/StatsColumn/QuestLevel/DifficultyLabel

var _mission_id: String = ""

func _ready() -> void:
	custom_minimum_size = Vector2(PLATE_SIZE.x, PLATE_SIZE.y + BADGE_TOP_MARGIN)
	plate_button.pressed.connect(_on_pressed)

func configure(
	mission_id: String,
	mission_name: String,
	energy: int,
	battles: int,
	difficulty: String,
	state: RowState
) -> void:
	_mission_id = mission_id
	name_label.text = mission_name
	energy_label.text = str(energy)
	battles_label.text = str(battles)

	var difficulty_text: String = difficulty.strip_edges()
	if difficulty_text != "":
		difficulty_label.text = difficulty_text
		difficulty_label.visible = true
	else:
		difficulty_label.visible = false

	_apply_plate_textures()
	_apply_status_badge(state)

func _apply_plate_textures() -> void:
	plate_button.texture_normal = PLATE_IDLE
	plate_button.texture_hover = PLATE_IDLE
	plate_button.texture_focused = PLATE_IDLE
	plate_button.texture_pressed = PLATE_PRESSED

func _apply_status_badge(state: RowState) -> void:
	var badge: Texture2D = BADGE_NEW
	if state == RowState.CLEAR:
		badge = BADGE_COMPLETE
	status_badge.texture = badge
	status_badge.visible = true
	var badge_size: Vector2 = badge.get_size()
	status_badge.offset_left = BADGE_LEFT
	status_badge.offset_top = PLATE_TOP - BADGE_SPLIT_LINE_Y
	status_badge.offset_right = status_badge.offset_left + badge_size.x
	status_badge.offset_bottom = status_badge.offset_top + badge_size.y

func _on_pressed() -> void:
	if _mission_id != "":
		row_pressed.emit(_mission_id)
