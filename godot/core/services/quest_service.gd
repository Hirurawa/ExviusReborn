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
			var parsed_rewards: Array[String] = []
			var raw_reward = str(row.get("reward", ""))
			if raw_reward != "":
				var reward_chunks = raw_reward.split(",", false)
				for chunk in reward_chunks:
					var parts = chunk.split(":")
					if parts.size() >= 3:
						var type = parts[0]
						var id = parts[1]
						var amount = parts[2]
						var name = ""

						if type == "20":
							var item_data = GameDatabase.get_item(id)
							if not item_data.is_empty():
								name = str(item_data.get("name", ""))
						elif type == "21":
							var equip_data = GameDatabase.get_equipment(id)
							if not equip_data.is_empty():
								name = str(equip_data.get("name", ""))
						elif type == "22":
							if typeof(StaticData.game_data_materia) == TYPE_DICTIONARY and StaticData.game_data_materia.has(str(id)):
								var materia_data = StaticData.game_data_materia[str(id)]
								if typeof(materia_data) == TYPE_DICTIONARY:
									name = str(materia_data.get("name", ""))

						if name != "":
							parsed_rewards.append(name + " x" + amount)
						else:
							parsed_rewards.append(chunk)
					else:
						parsed_rewards.append(chunk)

			quests_dict[quest_id] = {
				"id": quest_id,
				"name": str(row.get("questName", "")),
				"tasks": [],
				"rewards": parsed_rewards
			}

		var raw_task = row.get("task")
		if raw_task != null:
			var task_str = str(raw_task)
			if task_str != "":
				var task_dict: Dictionary = {
					"text": task_str,
					"requirements": []
				}

				var target_type = str(row.get("targetType", ""))
				if target_type == "1":
					var target_param = str(row.get("targetParam", ""))
					if target_param != "":
						var item_chunks = target_param.split(",", false)
						for chunk in item_chunks:
							var parts = chunk.split(":")
							if parts.size() >= 3:
								var type = parts[0]
								var id = parts[1]
								var amount = parts[2]
								var name = ""

								if type == "20":
									var item_data = GameDatabase.get_item(id)
									if not item_data.is_empty():
										name = str(item_data.get("name", ""))
								elif type == "21":
									var equip_data = GameDatabase.get_equipment(id)
									if not equip_data.is_empty():
										name = str(equip_data.get("name", ""))
								elif type == "22":
									if typeof(StaticData.game_data_materia) == TYPE_DICTIONARY and StaticData.game_data_materia.has(str(id)):
										var materia_data = StaticData.game_data_materia[str(id)]
										if typeof(materia_data) == TYPE_DICTIONARY:
											name = str(materia_data.get("name", ""))

								if name != "":
									var current_count = InventoryService.get_item_count(type, id)
									task_dict["requirements"].append(name + " " + str(current_count) + "/" + amount)

				elif target_type == "2":
					var target_param = str(row.get("targetParam", ""))
					if target_param != "":
						var monster_chunks = target_param.split(",", false)
						for chunk in monster_chunks:
							var parts = chunk.split(":")
							if parts.size() >= 2:
								var dict_id = parts[0]
								var amount = parts[1]
								var name = GameDatabase.get_monster_name(dict_id)
								if name != "":
									task_dict["requirements"].append(name + " 0/" + amount)
								else:
									task_dict["requirements"].append(chunk)
							else:
								task_dict["requirements"].append(chunk)
				quests_dict[quest_id]["tasks"].append(task_dict)

	var result: Array[Dictionary] = []
	for key in quests_dict:
		result.append(quests_dict[key])

	return result
