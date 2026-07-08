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
			var raw_rewards_array: Array[Dictionary] = []
			var raw_reward = str(row.get("reward", ""))
			if raw_reward != "":
				var reward_chunks = raw_reward.split(",", false)
				for chunk in reward_chunks:
					var parts = chunk.split(":")
					if parts.size() >= 3:
						var type = parts[0]
						var id = parts[1]
						var amount = parts[2]
						var quest_name = ""

						raw_rewards_array.append({"type": type, "id": id, "amount": int(amount)})

						if type == "20":
							var item_data = GameDatabase.get_item(id)
							if not item_data.is_empty():
								quest_name = str(item_data.get("quest_name", ""))
						elif type == "21":
							var equip_data = GameDatabase.get_equipment(id)
							if not equip_data.is_empty():
								quest_name = str(equip_data.get("quest_name", ""))
						elif type == "22":
							var materia_data = GameDatabase.get_materia(int(id))
							if not materia_data.is_empty():
								quest_name = str(materia_data.get("quest_name", ""))

						if quest_name != "":
							parsed_rewards.append(quest_name + " x" + amount)
						else:
							parsed_rewards.append(chunk)
					else:
						parsed_rewards.append(chunk)

			quests_dict[quest_id] = {
				"id": quest_id,
				"name": str(row.get("questName", "")),
				"tasks": [],
				"rewards": parsed_rewards,
				"raw_rewards": raw_rewards_array,
				"openSwitch": str(row.get("openSwitch", ""))
			}

		var raw_task = row.get("task")
		if raw_task != null:
			var task_str = str(raw_task)
			if task_str != "":
				var task_dict: Dictionary = {
					"text": task_str,
					"requirements": [],
					"target_type": str(row.get("targetType", ""))
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
								var task_name = ""

								if type == "20":
									var item_data = GameDatabase.get_item(id)
									if not item_data.is_empty():
										task_name = str(item_data.get("task_name", ""))
								elif type == "21":
									var equip_data = GameDatabase.get_equipment(id)
									if not equip_data.is_empty():
										task_name = str(equip_data.get("task_name", ""))
								elif type == "22":
									var materia_data = GameDatabase.get_materia(int(id))
									if not materia_data.is_empty():
										task_name = str(materia_data.get("task_name", ""))

								if task_name != "":
									var current_count = InventoryService.get_item_count(type, id)
									task_dict["requirements"].append(task_name + " " + str(current_count) + "/" + amount)
									task_dict["raw_requirements"] = task_dict.get("raw_requirements", [])
									task_dict["raw_requirements"].append({"type": type, "id": id, "amount": int(amount)})

				elif target_type == "2":
					var target_param = str(row.get("targetParam", ""))
					if target_param != "":
						var monster_chunks = target_param.split(",", false)
						for chunk in monster_chunks:
							var parts = chunk.split(":")
							if parts.size() >= 2:
								var dict_id = parts[0]
								var amount = parts[1]
								var monster_name = GameDatabase.get_monster_name(dict_id)
								if monster_name != "":
									var current_count = PlayerProfile.monster_kill_progress.get(str(dict_id), 0)
									task_dict["requirements"].append(monster_name + " " + str(current_count) + "/" + amount)
									task_dict["raw_requirements"] = task_dict.get("raw_requirements", [])
									task_dict["raw_requirements"].append({"id": dict_id, "amount": int(amount)})
								else:
									task_dict["requirements"].append(chunk)
							else:
								task_dict["requirements"].append(chunk)
				quests_dict[quest_id]["tasks"].append(task_dict)

	var result: Array[Dictionary] = []
	for key in quests_dict:
		result.append(quests_dict[key])

	return result
