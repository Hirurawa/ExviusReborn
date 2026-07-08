extends Control
class_name DungeonMissionListPopup

# Dumb UI: mission list + mission challenges panels. Emits signals on user action.
# No DB or game-state logic.

signal mission_selected(mission_id: String)
signal home_pressed
signal back_pressed

const ROW_SCENE: PackedScene = preload("res://features/outgame/map/DungeonMissionListRow.tscn")
const CHALLENGE_ROW_SCENE: PackedScene = preload("res://features/outgame/map/DungeonMissionChallengeRow.tscn")
const CONTENT_WIDTH: float = 640.0
const CONTENT_PIVOT: Vector2 = Vector2(320.0, 360.0)
const INITIAL_CHALLENGE_NAME: String = "complete the quest"
const CHALLENGE_ROW_MAX_HEIGHT: float = 128.0

@onready var content_root: Control = $ContentRoot
@onready var title_label: Label = $HeaderLayer/HeaderAnchor/TitlePlate/TitleLabel
@onready var mission_list_panel: VBoxContainer = $ContentRoot/VBoxContainer/MissionListPanel
@onready var list_host: VBoxContainer = $ContentRoot/VBoxContainer/MissionListPanel/ScrollContainer/ListHost
@onready var empty_label: Label = $ContentRoot/VBoxContainer/MissionListPanel/EmptyLabel
@onready var list_scroll_container: ScrollContainer = $ContentRoot/VBoxContainer/MissionListPanel/ScrollContainer
@onready var challenges_panel: VBoxContainer = $ContentRoot/VBoxContainer/MissionChallengesPanel
@onready var challenges_area: Control = $ContentRoot/VBoxContainer/MissionChallengesPanel/ChallengesArea
@onready var challenges_host: VBoxContainer = $ContentRoot/VBoxContainer/MissionChallengesPanel/ChallengesArea/ChallengesHost
@onready var initial_header: Control = $ContentRoot/VBoxContainer/MissionChallengesPanel/ChallengesArea/ChallengesHost/InitialHeader
@onready var initial_rows_host: VBoxContainer = $ContentRoot/VBoxContainer/MissionChallengesPanel/ChallengesArea/ChallengesHost/InitialRowsHost
@onready var achievement_header: Control = $ContentRoot/VBoxContainer/MissionChallengesPanel/ChallengesArea/ChallengesHost/AchievementHeader
@onready var achievement_rows_host: VBoxContainer = $ContentRoot/VBoxContainer/MissionChallengesPanel/ChallengesArea/ChallengesHost/AchievementRowsHost
@onready var next_button: TextureButton = $ContentRoot/VBoxContainer/MissionChallengesPanel/ChallengesArea/ChallengesHost/NextButton
@onready var back_button: TextureButton = $HeaderLayer/HeaderAnchor/BackButton
@onready var home_button: TextureButton = $HeaderLayer/HeaderAnchor/HomeButton

var _pending_init: Dictionary = {}
var _dungeon_name: String = ""
var _missions: Array[Dictionary] = []
var _selected_mission_id: String = ""
var _showing_challenges: bool = false

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	home_button.pressed.connect(_on_home_pressed)
	next_button.pressed.connect(_on_next_pressed)
	if not _pending_init.is_empty():
		_apply_init(_pending_init)
		_pending_init.clear()
	call_deferred("_apply_content_scale")

func init_scene(params: Dictionary) -> void:
	if is_node_ready():
		_apply_init(params)
	else:
		_pending_init = params

func _apply_init(params: Dictionary) -> void:
	_dungeon_name = str(params.get("dungeon_name", ""))
	_missions.clear()
	_selected_mission_id = ""
	_showing_challenges = false
	title_label.text = _dungeon_name if _dungeon_name != "" else "Missions"

	var missions_var: Variant = params.get("missions", [])
	if not (missions_var is Array):
		_show_empty_state()
		return

	for mission_value in missions_var:
		if mission_value is Dictionary:
			_missions.append(mission_value)
	if _missions.is_empty():
		_show_empty_state()
		return

	_show_mission_list()

func _add_mission_row(mission: Dictionary) -> void:
	var mission_id: String = str(mission.get("missionId", ""))
	if mission_id == "":
		return

	var mission_name: String = str(mission.get("name", ""))
	if mission_name == "":
		mission_name = mission_id

	var row: DungeonMissionListRow = ROW_SCENE.instantiate() as DungeonMissionListRow
	if row == null:
		return
	list_host.add_child(row)
	row.configure(
		mission_id,
		mission_name,
		int(mission.get("cost", 0)),
		int(mission.get("waveCount", 0)),
		str(mission.get("difficulty", "")),
		_parse_row_state(str(mission.get("row_state", "default")))
	)
	row.row_pressed.connect(_on_row_pressed)

func _parse_row_state(raw_state: String) -> DungeonMissionListRow.RowState:
	match raw_state.to_lower():
		"achieving":
			return DungeonMissionListRow.RowState.ACHIEVING
		"clear":
			return DungeonMissionListRow.RowState.CLEAR
		_:
			return DungeonMissionListRow.RowState.DEFAULT

func _show_empty_state() -> void:
	_showing_challenges = false
	mission_list_panel.visible = true
	challenges_panel.visible = false
	empty_label.visible = true
	list_scroll_container.visible = false
	_clear_list()
	_clear_challenge_rows()

func _show_mission_list() -> void:
	_showing_challenges = false
	_selected_mission_id = ""
	title_label.text = _dungeon_name if _dungeon_name != "" else "Missions"
	mission_list_panel.visible = true
	challenges_panel.visible = false
	empty_label.visible = false
	list_scroll_container.visible = true
	_clear_list()
	for mission in _missions:
		_add_mission_row(mission)

func _show_challenges(mission_id: String) -> void:
	var mission: Dictionary = _find_mission(mission_id)
	if mission.is_empty():
		return

	_selected_mission_id = mission_id
	_showing_challenges = true
	var mission_name: String = str(mission.get("name", ""))
	if mission_name == "":
		mission_name = mission_id
	title_label.text = mission_name

	mission_list_panel.visible = false
	challenges_panel.visible = true
	_populate_challenge_rows(mission)

func _find_mission(mission_id: String) -> Dictionary:
	for mission in _missions:
		if str(mission.get("missionId", "")) == mission_id:
			return mission
	return {}

func _populate_challenge_rows(mission: Dictionary) -> void:
	_clear_challenge_rows()
	var challenges_var: Variant = mission.get("challenges", [])
	var challenges: Array = challenges_var if challenges_var is Array else []
	var sections: Dictionary = _split_challenges(challenges)
	var objectives_var: Variant = mission.get("objectives", null)
	var show_stars: bool = objectives_var is Array
	var objectives: Array = objectives_var if show_stars else []

	_set_section_visible(initial_header, initial_rows_host, sections["initial"], objectives, 0)
	var achievement_offset: int = sections["initial"].size()
	_set_section_visible(achievement_header, achievement_rows_host, sections["achievement"], objectives, achievement_offset)
	#call_deferred("_fit_challenge_rows")

func _set_section_visible(
	section_header: Control,
	rows_host: VBoxContainer,
	challenges: Array,
	objectives: Array,
	objective_offset: int
) -> void:
	var has_rows: bool = not challenges.is_empty()
	section_header.visible = has_rows
	rows_host.visible = has_rows
	if not has_rows:
		return

	for index in range(challenges.size()):
		var challenge: Dictionary = challenges[index]
		if challenge.is_empty():
			continue
		var task_text: String = str(challenge.get("string", ""))
		var lapis_amount: int = _lapis_amount_from_reward(challenge.get("reward"))
		var completed: bool = false
		var objective_index: int = objective_offset + index
		if objective_index >= 0 and objective_index < objectives.size():
			completed = bool(objectives[objective_index])
		var row: DungeonMissionChallengeRow = CHALLENGE_ROW_SCENE.instantiate() as DungeonMissionChallengeRow
		if row == null:
			continue
		rows_host.add_child(row)
		row.configure(task_text, lapis_amount, completed)

func _split_challenges(challenges: Array) -> Dictionary:
	var initial: Array = []
	var achievement: Array = []
	if challenges.is_empty():
		return {"initial": initial, "achievement": achievement}

	var first: Dictionary = challenges[0] if challenges[0] is Dictionary else {}
	if str(first.get("string", "")).strip_edges().to_lower() == INITIAL_CHALLENGE_NAME:
		initial.append(first)
		for index in range(1, challenges.size()):
			if challenges[index] is Dictionary:
				achievement.append(challenges[index])
	else:
		for challenge_value in challenges:
			if challenge_value is Dictionary:
				achievement.append(challenge_value)
	return {"initial": initial, "achievement": achievement}

func _lapis_amount_from_reward(reward: Variant) -> int:
	if not (reward is Array):
		return 0
	var reward_parts: Array = reward
	if reward_parts.size() < 3:
		return 0
	if str(reward_parts[0]).to_upper() != "LAPIS":
		return 0
	return int(reward_parts[2])

func _clear_list() -> void:
	for child in list_host.get_children():
		child.queue_free()

func _clear_challenge_rows() -> void:
	for child in initial_rows_host.get_children():
		child.queue_free()
	for child in achievement_rows_host.get_children():
		child.queue_free()
	initial_header.visible = false
	achievement_header.visible = false
#
#func _fit_challenge_rows(allow_retry: bool = true) -> void:
	#if not challenges_panel.visible:
		#return
#
	#var row_count: int = initial_rows_host.get_child_count() + achievement_rows_host.get_child_count()
	#if row_count == 0:
		#return
#
	#if challenges_panel.size.y <= 0.0:
		#if allow_retry:
			#call_deferred("_fit_challenge_rows", false)
		#return
#
	##for child in initial_rows_host.get_children():
		##if child is DungeonMissionChallengeRow:
			##(child as DungeonMissionChallengeRow).set_row_height(CHALLENGE_ROW_MAX_HEIGHT)
	##for child in achievement_rows_host.get_children():
		##if child is DungeonMissionChallengeRow:
			##(child as DungeonMissionChallengeRow).set_row_height(CHALLENGE_ROW_MAX_HEIGHT)
#
	#challenges_area.custom_minimum_size = Vector2(CONTENT_WIDTH, challenges_host.get_minimum_size().y)

func _apply_content_scale() -> void:
	if not is_node_ready() or content_root == null:
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var viewport_width: float = viewport.get_visible_rect().size.x
	content_root.pivot_offset = CONTENT_PIVOT
	if viewport_width <= 0.0 or viewport_width >= CONTENT_WIDTH:
		content_root.scale = Vector2.ONE
		return
	var scale_factor: float = viewport_width / CONTENT_WIDTH
	content_root.scale = Vector2(scale_factor, scale_factor)

func _on_row_pressed(mission_id: String) -> void:
	_show_challenges(mission_id)

func _on_next_pressed() -> void:
	if _selected_mission_id != "":
		mission_selected.emit(_selected_mission_id)

func _on_back_pressed() -> void:
	if _showing_challenges:
		_show_mission_list()
		return
	back_pressed.emit()

func _on_home_pressed() -> void:
	home_pressed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		call_deferred("_apply_content_scale")
		#if _showing_challenges:
			#call_deferred("_fit_challenge_rows")
