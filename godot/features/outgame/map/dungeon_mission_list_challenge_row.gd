extends Control
class_name DungeonMissionChallengeRow

@onready var reward_l: Label = $VBoxContainer/QuestMissionplate/RewardLabel
@onready var task_l: Label = $VBoxContainer/QuestMissionplate/TaskLabel
@onready var star_i: TextureRect = $VBoxContainer/QuestMissionplate/QuestMissionstarFrame/QuestMissionstar
@onready var mission_plate: TextureRect = $VBoxContainer/QuestMissionplate
@onready var reward_icon: TextureRect = $"VBoxContainer/QuestMissionplate/RewardIcon"

const MISSION_CLEAR: Texture2D = preload("res://assets/ui/quest/quest_missionplate_clear.tres")

func configure(task_text: String, reward: Array, completed: bool) -> void:
	task_l.text = task_text
	var data = {}
	var reward_type = reward[0] as Types.Category_types
	match reward_type:
		Types.Category_types.LAPIS:
			var lapis_amount: int = 0
			if reward.size() >= 3:
				lapis_amount = int(reward[2])
			elif reward.size() >= 2:
				lapis_amount = int(reward[1])
			if lapis_amount > 0:
				data["name"] = "Lapis"
				data["icon_path"] = "res://assets/ui/icon/icon_lapis.png"
		Types.Category_types.UNIT:
			data = GameDatabase.get_unit(int(reward[1]))
			data["name"] = data.get("unitName")
			data["icon_path"] = "res://assets/unit_illustrations/unit_ills_%s.png" % str(data.get("unitId"))
		Types.Category_types.ITEM:
			data = GameDatabase.get_item(int(reward[1]))
			var file_name = data.get("iconFile")
			data["icon_path"] = "res://assets/items/" + file_name
		Types.Category_types.EQUIP:
			data = GameDatabase.get_equipment(reward[1])
			var file_name = data.get("iconFile")
			data["icon_path"] = "res://assets/equip/" + file_name
		Types.Category_types.MATERIA:
			data = GameDatabase.get_materia(int(reward[1]))
			var file_name = data.get("iconFile")
			data["icon_path"] = "res://assets/materia/" + file_name
		Types.Category_types.KEYITEM:
			data = GameDatabase.get_important_item(int(reward[1]))
			var file_name = data.get("iconFile")
			data["icon_path"] = "res://assets/items/" + file_name
		Types.Category_types.VISIONCARD:
			data["name"] = "Vision Card"
		Types.Category_types.RECIPE:
			data = GameDatabase.get_recipe(reward[1])
		_:
			push_warning("Unsupported mission first-clear reward type: %s" % reward_type)
	
	if int(reward[2]) != 1:
		reward_l.text = "%s x %s" % [reward[2], data.get("name", "")]
	else:
		reward_l.text = data.get("name", "")
	
	var reward_texture_path = data.get("icon_path", "")
	if ResourceLoader.exists(reward_texture_path):
		reward_icon.texture = ResourceLoader.load(reward_texture_path) as Texture2D
	star_i.visible = completed
	if completed:
		mission_plate.texture = MISSION_CLEAR
