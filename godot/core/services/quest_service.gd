extends Node
## QuestService handles fetching and processing quest data from GameDatabase.

func get_quests_for_town(town_id: String) -> Array[Dictionary]:
	var raw_quests: Array = GameDatabase.get_quests_for_town(town_id)

	# Dictionary to group tasks by questId
	var quests_dict: Dictionary = {}

	for row in raw_quests:
		var quest_id = str(row.get("questId", ""))
		if quest_id == "":
			continue

		var switch_info = row.get("switchInfo")
		# Filter out locked quests based on switchInfo (0 or null means unlocked)
		if switch_info != null and typeof(switch_info) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			var switch_str = str(switch_info)
			if switch_str != "0" and switch_str != "":
				if not SwitchService.is_unlocked(switch_str):
					continue

		if not quests_dict.has(quest_id):
			quests_dict[quest_id] = {
				"id": quest_id,
				"name": str(row.get("questName", "")),
				"tasks": []
			}

		var raw_task = row.get("task")
		if raw_task != null:
			var task = str(raw_task)
			if task != "":
				quests_dict[quest_id]["tasks"].append(task)

	var result: Array[Dictionary] = []
	for key in quests_dict:
		result.append(quests_dict[key])

	return result
