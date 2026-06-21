extends Control
class_name DungeonMissionListPopup

# Dumb UI: receives display data via init_scene(), renders mission rows, and emits
# signals when the user picks a mission or presses Back/Home. No DB or game-state logic.

signal mission_selected(mission_id: String)
signal home_pressed
signal back_pressed

const ROW_SCENE: PackedScene = preload("res://features/outgame/map/DungeonMissionListRow.tscn")
const CONTENT_WIDTH: float = 640.0
const CONTENT_PIVOT: Vector2 = Vector2(320.0, 280.0)

@onready var content_root: Control = $ContentRoot
@onready var title_label: Label = $HeaderLayer/HeaderAnchor/TitlePlate/TitleLabel
@onready var list_host: VBoxContainer = $ContentRoot/VBoxContainer/ScrollContainer/ListHost
@onready var empty_label: Label = $ContentRoot/VBoxContainer/EmptyLabel
@onready var scroll_container: ScrollContainer = $ContentRoot/VBoxContainer/ScrollContainer
@onready var back_button: TextureButton = $HeaderLayer/HeaderAnchor/BackButton
@onready var home_button: TextureButton = $HeaderLayer/HeaderAnchor/HomeButton

var _pending_init: Dictionary = {}

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	home_button.pressed.connect(_on_home_pressed)
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
	var dungeon_name: String = str(params.get("dungeon_name", ""))
	title_label.text = dungeon_name if dungeon_name != "" else "Missions"

	var missions_var: Variant = params.get("missions", [])
	if not (missions_var is Array):
		_show_empty_state()
		return

	var missions: Array[Dictionary] = []
	for mission_value in missions_var:
		if mission_value is Dictionary:
			missions.append(mission_value)
	if missions.is_empty():
		_show_empty_state()
		return

	_show_list_state()
	_clear_list()
	for mission in missions:
		_add_mission_row(mission)

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
	# Maps orchestrator-provided strings to row visuals; no MissionService access here.
	match raw_state.to_lower():
		"achieving":
			return DungeonMissionListRow.RowState.ACHIEVING
		"clear":
			return DungeonMissionListRow.RowState.CLEAR
		_:
			return DungeonMissionListRow.RowState.DEFAULT

func _show_empty_state() -> void:
	empty_label.visible = true
	scroll_container.visible = false
	_clear_list()

func _show_list_state() -> void:
	empty_label.visible = false
	scroll_container.visible = true

func _clear_list() -> void:
	for child in list_host.get_children():
		child.queue_free()

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
	mission_selected.emit(mission_id)

func _on_back_pressed() -> void:
	back_pressed.emit()

func _on_home_pressed() -> void:
	home_pressed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		call_deferred("_apply_content_scale")
