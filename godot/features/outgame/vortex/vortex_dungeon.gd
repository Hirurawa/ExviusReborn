extends Control

@onready var content = $VBoxContainer/ScrollContainer/Content
@onready var back_button = $UnitNamebgChara2/BackButton

var mission_list_scene: PackedScene = preload("res://features/outgame/map/DungeonMissionListRow.tscn")
const MISSION_POPUP_SCENE: PackedScene = preload("res://features/outgame/map/DungeonMissionListPopup.tscn")
var _mission_popup: DungeonMissionListPopup = null

enum Depth { AREA, DUNGEON, MISSION }

var current_depth: Depth = Depth.AREA

var incomplete_missions: Array[int] = [9001301,9001302,9001303,9001601,9001602,9001603,9003501,89911071,89911072]

# Store these so the Back button knows what to query
var selected_area_id: String = ""
var selected_dungeon_id: String = ""

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	_refresh_list()

func _populate_list(items: Array) -> void:
	for item in items:
		if current_depth == Depth.MISSION:
			var missions: Array[Dictionary] = _build_mission_popup_entries(GameDatabase.get_missions(str(selected_dungeon_id)))
			_open_mission_popup(item.name, missions)
		else:
			var btn = TextureButton.new()
			var banner_texture = "res://assets/spdungeon/" + item.get("iconFile")
			if ResourceLoader.exists(banner_texture):
				btn.texture_normal = ResourceLoader.load(banner_texture) as Texture2D
			
			# Bind the specific item's ID to the generic click handler
			btn.pressed.connect(_on_list_item_pressed.bind(str(item.get("areaId", item.get("dungeonId")))))
			
			content.add_child(btn)

func _refresh_list() -> void:
	# 1. Clear existing list items
	for child in content.get_children():
		child.queue_free()
	
	var current_items = []
	# 2. Query and populate based on state
	match current_depth:
		Depth.AREA:
			current_items = GameDatabase.get_vortex_areas()
		Depth.DUNGEON:
			current_items = GameDatabase.get_dungeons(selected_area_id)
		Depth.MISSION:
			current_items = GameDatabase.get_missions(selected_dungeon_id)
		
	_populate_list(current_items)

func _on_area_selected(area_id: String) -> void:
	selected_area_id = area_id
	current_depth = Depth.DUNGEON

func _on_dungeon_selected(dungeon_id: String) -> void:
	selected_dungeon_id = dungeon_id
	current_depth = Depth.MISSION

func _on_back_button_pressed() -> void:
	match current_depth:
		Depth.MISSION:
			_close_mission_popup()
			current_depth = Depth.DUNGEON
			_refresh_list()
		Depth.DUNGEON:
			current_depth = Depth.AREA
			selected_area_id = "" # Clear state
			_refresh_list()
		Depth.AREA:
			# We are already at the top. Let your UI Manager pop this entire scene.
			UIManager.pop()

func _on_list_item_pressed(item_id: String) -> void:
	match current_depth:
		Depth.AREA:
			selected_area_id = item_id
			current_depth = Depth.DUNGEON
			_refresh_list()
		Depth.DUNGEON:
			selected_dungeon_id = item_id
			current_depth = Depth.MISSION
			_refresh_list()
		Depth.MISSION:
			var result: Dictionary = MissionService.request_start_mission(item_id)
			if result.get("success", false) == true:
				UIManager.push("combat_ui", {"mission_id": item_id})
			else:
				print(str(result.get("error", "Could not start this mission.")))


func _open_mission_popup(dungeon_name: String, missions: Array[Dictionary]) -> void:
	_close_mission_popup()
	var popup: DungeonMissionListPopup = MISSION_POPUP_SCENE.instantiate() as DungeonMissionListPopup
	if popup == null:
		return

	add_child(popup)
	_mission_popup = popup
	popup.init_scene({
		"dungeon_name": dungeon_name,
		"missions": missions,
	})
	popup.mission_selected.connect(_on_list_item_pressed)

func _build_mission_popup_entries(missions: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for mission_value in missions:
		if not (mission_value is Dictionary):
			continue
		var mission: Dictionary = (mission_value as Dictionary).duplicate(true)
		var mission_id: String = str(mission.get("missionId", ""))
		if mission_id == "":
			continue
		#if not SwitchService.is_unlocked(mission.get("switchInfo")):
			#continue
		mission["row_state"] = _resolve_mission_row_state(mission_id)
		mission["challenges"] = GameDatabase.get_mission_challenges(mission_id)
		var progress: Variant = MissionService.cleared_missions.get(mission_id, {})
		if progress is Dictionary and (progress as Dictionary).has("objectives"):
			mission["objectives"] = (progress as Dictionary).get("objectives", [])
		entries.append(mission)
	return entries

func _resolve_mission_row_state(mission_id: String) -> String:
	var progress: Variant = MissionService.cleared_missions.get(mission_id, {})
	if progress is Dictionary and bool((progress as Dictionary).get("cleared", false)):
		return "clear"
	if mission_id == MissionService.last_entered_mission_id:
		return "achieving"
	return "default"

func _close_mission_popup() -> void:
	if _mission_popup != null and is_instance_valid(_mission_popup):
		_mission_popup.queue_free()
	_mission_popup = null
