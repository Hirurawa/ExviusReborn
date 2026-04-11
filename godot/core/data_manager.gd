extends Node

signal data_loaded
signal login_success
signal login_failed(error_code: int)
signal register_success
signal register_failed(error_code: int)
signal account_updated(username: String)
signal rank_updated(rank: int, xp: int, next_rank_xp: int)
signal nrg_updated(current_nrg: int, max_nrg: int, time_until_next: float)
signal currency_updated(gil: int, lapis: int)
signal units_updated(units: Array)
signal items_updated(items: Dictionary)
signal friends_updated(friends: Object)
signal friend_action_result(success: bool, message: String)
signal parties_updated(parties: Array)
signal party_save_requested(new_parties: Array)
signal purchase_successful()
signal purchase_failed(error_message: String)

signal dungeon_missions_ready(mission_ids: Array)
signal mission_completed(rewards_text: String)
signal mission_failed(error_msg: String)
signal equip_successful()
signal equip_failed(error_message: String)

var server_connection: Node

var current_rank: int = 1
var current_xp: int = 0
var next_rank_xp: int = 100
var current_nrg: int = 0
var max_nrg: int = 0
var nrg_regen_rate_seconds: int = 300
var seconds_until_next_nrg: float = 0.0

var gil: int = 0
var lapis: int = 0

var owned_units_ids: Array = []
var owned_items: Dictionary = {"stackables": {}, "equipment": []}
var parties: Array = []

var game_data_units: Dictionary = {}
var game_data_items: Dictionary = {}
var game_data_equipment: Dictionary = {}
var game_data_worlds: Dictionary = {}
var game_data_dungeons: Dictionary = {}
var game_data_missions: Dictionary = {}
var game_data_skills_magic: Dictionary = {}
var game_data_skills_ability: Dictionary = {}
var game_data_limitbursts: Dictionary = {}
var game_data_materia: Dictionary = {}
var game_data_equipment_icons: Dictionary = {}
var game_data_monsters = []

var account_info: NakamaAPI.ApiAccount = null

func _ready() -> void:
	var server_script: GDScript = preload("res://core/server_connection.gd")
	server_connection = server_script.new()
	server_connection.name = "ServerConnection"
	add_child(server_connection)

	party_save_requested.connect(save_parties)

func _process(delta: float) -> void:
	if max_nrg > 0 and current_nrg < max_nrg:
		seconds_until_next_nrg -= delta
		if seconds_until_next_nrg <= 0:
			current_nrg += 1
			seconds_until_next_nrg = nrg_regen_rate_seconds
			nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
		else:
			# Still ticking, UI might want to know for the timer
			nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)

func authenticate(email: String, password: String) -> void:
	var result: int = await server_connection.authenticate_async(email, password)
	if result == OK:
		await _load_initial_data(email)
		login_success.emit()
	else:
		login_failed.emit(result)

func register(email: String, password: String, username: String) -> void:
	var result: int = await server_connection.register_async(email, password, username)
	if result == OK:
		await _load_initial_data(email)
		register_success.emit()
	else:
		register_failed.emit(result)

func logout() -> void:
	server_connection.logout()
	account_info = null

func update_account(new_username: String) -> bool:
	var result: int = await server_connection.update_account_async(new_username)
	if result == OK:
		account_info = await server_connection.get_account_async()
		account_updated.emit(account_info.user.username)
		return true
	return false

func _load_initial_data(email: String) -> void:
	if not AssetPatcher.patch_complete.is_connected(_on_patch_complete):
		AssetPatcher.patch_progress.connect(func(file_name, status):
			pass
		)
		AssetPatcher.patch_complete.connect(_on_patch_complete)

	AssetPatcher.server_connection = server_connection
	AssetPatcher.start_patching()
	await AssetPatcher.patch_complete
	var stats: Dictionary = await server_connection.read_player_stats_async()
	current_rank = int(stats.get("rank", 1))
	current_xp = int(stats.get("xp", 0))
	next_rank_xp = int(stats.get("next_rank_xp", 100))
	current_nrg = int(stats.get("current_nrg", 41))
	max_nrg = int(stats.get("max_nrg", 41))
	nrg_regen_rate_seconds = int(stats.get("nrg_regen_rate_seconds", 300))
	seconds_until_next_nrg = float(stats.get("seconds_until_next_nrg", 0.0))
	rank_updated.emit(current_rank, current_xp, next_rank_xp)
	nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)

	owned_units_ids = await server_connection.read_player_units_async()
	_inject_final_stats(owned_units_ids)
	units_updated.emit(owned_units_ids)
	
	parties = await server_connection.get_parties_async()
	parties_updated.emit(parties)
	
	account_info = await server_connection.get_account_async()
	if account_info:
		var wallet_str: String = account_info.wallet
		if wallet_str and wallet_str != "":
			var wallet: Variant = JSON.parse_string(wallet_str)
			if wallet and wallet is Dictionary:
				_update_wallet_data(wallet)

	data_loaded.emit()

#func _inject_final_stats(units: Array) -> Array:
	#for unit in units:
		#if typeof(unit) == TYPE_DICTIONARY:
			#unit["final_stats"] = StatCalculator.calculate_final_stats(unit)
	#return units

func _sanitize_floats_to_ints(data: Variant) -> Variant:
	if typeof(data) == TYPE_DICTIONARY:
		var new_dict: Dictionary = {}
		for key in data:
			new_dict[key] = _sanitize_floats_to_ints(data[key])
		return new_dict
	elif typeof(data) == TYPE_ARRAY:
		var new_array: Array = []
		for item in data:
			new_array.append(_sanitize_floats_to_ints(item))
		return new_array
	elif typeof(data) == TYPE_FLOAT:
		if fmod(data, 1.0) == 0.0:
			return int(data)
	return data

func _on_patch_complete() -> void:
	game_data_units = _sanitize_floats_to_ints(AssetPatcher.get_data("units"))
	game_data_items = _sanitize_floats_to_ints(AssetPatcher.get_data("items"))
	game_data_equipment = _sanitize_floats_to_ints(AssetPatcher.get_data("equipment"))
	game_data_worlds = _sanitize_floats_to_ints(AssetPatcher.get_data("worlds"))
	game_data_dungeons = _sanitize_floats_to_ints(AssetPatcher.get_data("dungeons"))
	game_data_skills_magic = _sanitize_floats_to_ints(AssetPatcher.get_data("skills_magic"))
	game_data_skills_ability = _sanitize_floats_to_ints(AssetPatcher.get_data("skills_ability"))
	game_data_limitbursts = _sanitize_floats_to_ints(AssetPatcher.get_data("limitbursts"))
	game_data_materia = _sanitize_floats_to_ints(AssetPatcher.get_data("materia"))
	game_data_equipment_icons = _sanitize_floats_to_ints(AssetPatcher.get_data("equipment-icons"))
	game_data_monsters = _sanitize_floats_to_ints(AssetPatcher.get_data("monsters"))

func _update_wallet_data(wallet: Dictionary) -> void:
	gil = int(wallet.get("gil", 0))
	lapis = int(wallet.get("lapis", 0))
	currency_updated.emit(gil, lapis)

func add_rank_xp(xp_to_add: int) -> void:
	var result: Dictionary = await server_connection.add_rank_xp_async(xp_to_add)
	if not result.is_empty():
		current_rank = int(result.get("rank", current_rank))
		current_xp = int(result.get("xp", current_xp))
		next_rank_xp = int(result.get("next_rank_xp", next_rank_xp))
		current_nrg = int(result.get("current_nrg", current_nrg))
		max_nrg = int(result.get("max_nrg", max_nrg))
		nrg_regen_rate_seconds = int(result.get("nrg_regen_rate_seconds", nrg_regen_rate_seconds))
		seconds_until_next_nrg = float(result.get("seconds_until_next_nrg", seconds_until_next_nrg))
		rank_updated.emit(current_rank, current_xp, next_rank_xp)
		nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)

func add_currency(gil_to_add: int, lapis_to_add: int) -> void:
	var result: Dictionary = await server_connection.add_currency_async(gil_to_add, lapis_to_add)
	if result.has("wallet"):
		var wallet: Variant = JSON.parse_string(result.wallet) if result.wallet is String else result.wallet
		_update_wallet_data(wallet)

func request_buy_item(item_id: String, quantity: int) -> void:
	var result: Dictionary = await server_connection.buy_item_async(item_id, quantity)
	if not result.has("error"):
		if result.has("added_equipment"):
			if typeof(owned_items.get("equipment")) == TYPE_ARRAY:
				owned_items["equipment"].append_array(result.added_equipment)
			items_updated.emit(owned_items)
		if result.has("stackables"):
			owned_items["stackables"] = result.stackables
			items_updated.emit(owned_items)
		if result.has("wallet"):
			var wallet: Variant = JSON.parse_string(result.wallet) if result.wallet is String else result.wallet
			_update_wallet_data(wallet)
		purchase_successful.emit()
	else:
		purchase_failed.emit(result.get("error", "Unknown error"))

func save_parties(new_parties: Array) -> Dictionary:
	var result: Dictionary = await server_connection.save_parties_async(new_parties)
	if not result.has("error"):
		parties = new_parties
		parties_updated.emit(parties)
	return result

func assign_unit_to_party(party_index: int, slot_index: int, instance_id: String) -> void:
	if party_index >= 0 and party_index < parties.size():
		var new_parties: Array = parties.duplicate(true)
		new_parties[party_index]["units"][slot_index] = instance_id
		party_save_requested.emit(new_parties)

func summon_units(amount: int) -> Array:
	var summoned_units: Array = await server_connection.summon_units_async(amount)
	_inject_final_stats(summoned_units)
	owned_units_ids.append_array(summoned_units)
	units_updated.emit(owned_units_ids)
	return summoned_units

func add_unit_xp(instance_id: String, xp_amount: int) -> Dictionary:
	var result: Dictionary = await server_connection.add_unit_xp_async(instance_id, xp_amount)
	if not result.has("error"):
		owned_units_ids = await server_connection.read_player_units_async()
		_inject_final_stats(owned_units_ids)
		units_updated.emit(owned_units_ids)
	return result

func awaken_unit(instance_id: String) -> Dictionary:
	var result: Dictionary = await server_connection.awaken_unit_async(instance_id)
	if not result.has("error"):
		owned_units_ids = await server_connection.read_player_units_async()
		_inject_final_stats(owned_units_ids)
		units_updated.emit(owned_units_ids)
	return result

func request_equip_item(instance_id: String, slot_id: String, item_id: String) -> void:
	if item_id != "" and slot_id in ["r_hand", "l_hand"]:
		var item_data_dict: Dictionary = {}
		for item in owned_items.get("equipment", []):
			if item is Dictionary and item.get("instance_id", "") == item_id:
				var template_id: String = item.get("template_id", "")
				if game_data_equipment.has(template_id):
					item_data_dict = game_data_equipment[template_id]
				break

		if item_data_dict.get("is_twohanded", false):
			var other_hand: String = "l_hand" if slot_id == "r_hand" else "r_hand"
			await server_connection.equip_item_async(instance_id, other_hand, "")

	var result: Dictionary = await server_connection.equip_item_async(instance_id, slot_id, item_id)
	if not result.has("error"):
		owned_units_ids = await server_connection.read_player_units_async()
		_inject_final_stats(owned_units_ids)
		units_updated.emit(owned_units_ids)
		equip_successful.emit()
	else:
		equip_failed.emit(result.get("error", "Unknown error"))
		
func _inject_final_stats(units: Array) -> void:
	for i in range(units.size()):
		if units[i] is Dictionary:
			units[i]["final_stats"] = StatCalculator.calculate_final_stats(units[i])

func list_friends() -> NakamaAPI.ApiFriendList:
	var friends_list: NakamaAPI.ApiFriendList = await server_connection.list_friends_async()
	friends_updated.emit(friends_list)
	return friends_list

func add_friend(username: String) -> void:
	var result: int = await server_connection.add_friends_async(username)
	if result == OK:
		friend_action_result.emit(true, "Success")
		list_friends()
	else:
		friend_action_result.emit(false, "Error code: %d" % result)

func delete_friend(username: String) -> void:
	var result: int = await server_connection.delete_friends_async(username)
	if result == OK:
		friend_action_result.emit(true, "Success")
		list_friends()
	else:
		friend_action_result.emit(false, "Error code: %d" % result)

func perform_mission(mission_id: String) -> Dictionary:
	var result: Dictionary = await server_connection.perform_mission_async(mission_id)
	if not result.has("error"):
		if result.has("stats"):
			var stats = result.stats
			current_rank = int(stats.get("rank", current_rank))
			current_xp = int(stats.get("xp", current_xp))
			next_rank_xp = int(stats.get("next_rank_xp", next_rank_xp))
			current_nrg = int(stats.get("current_nrg", current_nrg))
			max_nrg = int(stats.get("max_nrg", max_nrg))
			nrg_regen_rate_seconds = int(stats.get("nrg_regen_rate_seconds", nrg_regen_rate_seconds))
			seconds_until_next_nrg = float(stats.get("seconds_until_next_nrg", seconds_until_next_nrg))
			rank_updated.emit(current_rank, current_xp, next_rank_xp)
			nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
		if result.has("wallet"):
			var wallet = JSON.parse_string(result.wallet) if result.wallet is String else result.wallet
			_update_wallet_data(wallet)
	return result

func request_dungeon_missions(mission_ids: Array) -> void:
	var detailed_missions: Dictionary = await server_connection.get_dungeon_missions_async(mission_ids)
	for mission_id in mission_ids:
		var mission_data = detailed_missions.get(str(mission_id), {})
		if not mission_data.is_empty():
			game_data_missions[str(mission_id)] = mission_data # Cache it
	dungeon_missions_ready.emit(mission_ids)

func request_perform_mission(mission_id: String) -> void:
	var result: Dictionary = await perform_mission(mission_id)

	if result.has("error"):
		mission_failed.emit(str(result.error))
	else:
		var rewards_text: String = ""
		var mission_data: Dictionary = game_data_missions.get(mission_id, {})

		if mission_data.has("gil"):
			rewards_text += "Gil +%s\n" % str(int(mission_data.get("gil", 0)))
		if mission_data.has("exp"):
			rewards_text += "Rank EXP +%s\n" % str(int(mission_data.get("exp", 0)))

		mission_completed.emit(rewards_text)


func get_equipment_template_id(instance_id: String) -> String:
	for item in owned_items.get("equipment", []):
		if not item is Dictionary: continue
		if item.get("instance_id", "") == instance_id:
			return item.get("template_id", "")
	return ""

func get_available_equipment_for_slot(slot_id: String, allowed_equips: Array) -> Array:
	var available_items: Array = []
	for item in owned_items.get("equipment", []):
		if not item is Dictionary: continue
		var instance_id: String = item.get("instance_id", "")
		var template_id: String = item.get("template_id", "")

		var item_data: Variant = game_data_equipment.get(template_id)
		if not item_data: continue

		var item_data_dict: Dictionary = item_data as Dictionary

		var item_type_id: int = item_data_dict.get("type_id", -1)
		var is_valid_slot: bool = false

		var item_slot: String = item_data_dict.get("slot", "")
		if "hand" in slot_id and (item_slot == "Weapon" or item_slot == "Shield"):
			is_valid_slot = true
		elif "head" in slot_id and item_slot == "Headgear":
			is_valid_slot = true
		elif "body" in slot_id and item_slot == "Chest":
			is_valid_slot = true
		elif "acc_" in slot_id and item_slot == "Accessory":
			is_valid_slot = true
		elif "ability_" in slot_id and item_slot == "Materia":
			is_valid_slot = true

		if not is_valid_slot: continue
		if item_type_id not in allowed_equips and item_type_id != -1: continue

		# Combine the instance wrapper data with static stats for the UI
		var combined_item: Dictionary = item_data_dict.duplicate()
		combined_item["instance_id"] = instance_id
		combined_item["template_id"] = template_id
		combined_item["equipped_to"] = item.get("equipped_to", null)

		available_items.append(combined_item)

	return available_items
