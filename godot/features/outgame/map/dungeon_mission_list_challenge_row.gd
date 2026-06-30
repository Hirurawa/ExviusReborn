extends Control
class_name DungeonMissionChallengeRow

# Dumb UI: one mission challenge row (star, task text, lapis reward).

const STAR_SILVER: Texture2D = preload("res://assets/ui/quest/quest_missionstar_silver.tres")
const STAR_GOLD: Texture2D = preload("res://assets/ui/quest/quest_missionstar.tres")
const LAPIS_ICON: Texture2D = preload("res://assets/ui/quest/lapis_icon1.tres")

const ROW_WIDTH: float = 640.0
const ROW_HEIGHT: float = 128.0
const LAPIS_LEFT: float = 572.0
const LAPIS_RIGHT: float = 624.0
const REWARD_LAPIS_GAP: float = 8.0

@onready var row_background: HBoxContainer = $RowBackground
@onready var overlay: Control = $Overlay
@onready var star_icon: TextureRect = $Overlay/StarIcon
@onready var task_label: Label = $Overlay/TaskLabel
@onready var reward_label: Label = $Overlay/RewardLabel
@onready var lapis_icon: TextureRect = $Overlay/LapisIcon

func _ready() -> void:
	set_row_height(ROW_HEIGHT)

func set_row_height(height: float) -> void:
	var row_height: float = ROW_HEIGHT
	var scale: float = row_height / ROW_HEIGHT

	custom_minimum_size = Vector2(ROW_WIDTH, row_height)
	row_background.position = Vector2.ZERO
	row_background.size = Vector2(ROW_WIDTH, row_height)
	overlay.position = Vector2.ZERO
	overlay.size = Vector2(ROW_WIDTH, row_height)
	_apply_overlay_layout(scale)

func configure(task_text: String, lapis_amount: int, completed: bool, show_star: bool) -> void:
	task_label.text = task_text
	reward_label.text = "Lapis x %d" % lapis_amount
	star_icon.visible = show_star
	if show_star:
		star_icon.texture = STAR_GOLD if completed else STAR_SILVER
	reward_label.visible = lapis_amount > 0
	lapis_icon.visible = lapis_amount > 0

func _apply_overlay_layout(scale: float) -> void:
	_set_rect(star_icon, 8.0, 28.0, 80.0, 100.0, scale)
	_set_rect(task_label, 96.0, 24.0, 520.0, 56.0, scale)
	_set_rect(lapis_icon, LAPIS_LEFT, 68.0, LAPIS_RIGHT, 120.0, scale)
	var reward_right: float = LAPIS_LEFT * scale - REWARD_LAPIS_GAP * scale
	_set_rect(reward_label, 96.0, 72.0, reward_right, 104.0, scale)

func _set_rect(node: Control, left: float, top: float, right: float, bottom: float, scale: float) -> void:
	node.offset_left = left * scale
	node.offset_top = top * scale
	node.offset_right = right * scale
	node.offset_bottom = bottom * scale
