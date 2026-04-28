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
signal mission_progress_loaded(latest_mission_id: String)

var server_connection: Node

var current_rank: int = 1
var current_xp: int = 0
var next_rank_xp: int = 100
var current_nrg: int = 0
var max_nrg: int = 0
var nrg_regen_rate_seconds: int = 300
var seconds_until_next_nrg: float = 0.0
var last_entered_mission_id: String = ""

var gil: int = 0
var lapis: int = 0

var owned_units_ids: Array = []

var last_played_dungeon_name: String = ""
var cleared_missions: Dictionary = {}
var latest_cleared_mission_id: String = ""
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
var game_data_skills_passive: Dictionary = {}
var game_data_limitbursts: Dictionary = {}
var game_data_materia: Dictionary = {}
var game_data_equipment_icons: Dictionary = {}
var game_data_monsters = []
var opcode_skill_schema: Dictionary = {}
var opcode_passive_schema: Dictionary = {}
var opcode_schemas_ready: bool = false
var opcode_schema_error: String = ""

const OPCODE_SKILL_SCHEMA_PATH: String = "res://features/battle/logic/skill_schema.json"
const OPCODE_PASSIVE_SCHEMA_PATH: String = "res://features/battle/logic/passive_schema.json"

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
	last_entered_mission_id = ""
	last_played_dungeon_name = ""

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
	assert(stats.has("rank"), "CRITICAL ERROR: stats is missing rank!")
	if not stats.has("rank"): push_error("CRITICAL ERROR: stats is missing rank!")
	current_rank = int(stats["rank"])
	assert(stats.has("xp"), "CRITICAL ERROR: stats is missing xp!")
	if not stats.has("xp"): push_error("CRITICAL ERROR: stats is missing xp!")
	current_xp = int(stats["xp"])
	assert(stats.has("next_rank_xp"), "CRITICAL ERROR: stats is missing next_rank_xp!")
	if not stats.has("next_rank_xp"): push_error("CRITICAL ERROR: stats is missing next_rank_xp!")
	next_rank_xp = int(stats["next_rank_xp"])
	assert(stats.has("current_nrg"), "CRITICAL ERROR: stats is missing current_nrg!")
	if not stats.has("current_nrg"): push_error("CRITICAL ERROR: stats is missing current_nrg!")
	current_nrg = int(stats["current_nrg"])
	assert(stats.has("max_nrg"), "CRITICAL ERROR: stats is missing max_nrg!")
	if not stats.has("max_nrg"): push_error("CRITICAL ERROR: stats is missing max_nrg!")
	max_nrg = int(stats["max_nrg"])
	assert(stats.has("nrg_regen_rate_seconds"), "CRITICAL ERROR: stats is missing nrg_regen_rate_seconds!")
	if not stats.has("nrg_regen_rate_seconds"): push_error("CRITICAL ERROR: stats is missing nrg_regen_rate_seconds!")
	nrg_regen_rate_seconds = int(stats["nrg_regen_rate_seconds"])
	assert(stats.has("seconds_until_next_nrg"), "CRITICAL ERROR: stats is missing seconds_until_next_nrg!")
	if not stats.has("seconds_until_next_nrg"): push_error("CRITICAL ERROR: stats is missing seconds_until_next_nrg!")
	seconds_until_next_nrg = float(stats["seconds_until_next_nrg"])
	last_entered_mission_id = str(stats.get("last_entered_mission_id", ""))
	if last_entered_mission_id != "":
		await _update_last_played_dungeon_from_mission(last_entered_mission_id)
	else:
		last_played_dungeon_name = ""
	await load_mission_progress()
	rank_updated.emit(current_rank, current_xp, next_rank_xp)
	nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)

	owned_items = await server_connection.read_player_items_async()
	items_updated.emit(owned_items)

	owned_units_ids = await server_connection.read_player_units_async()
	owned_units_ids = _hydrate_owned_units(owned_units_ids)
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
	game_data_skills_passive = _sanitize_floats_to_ints(AssetPatcher.get_data("skills_passive"))
	game_data_limitbursts = _sanitize_floats_to_ints(AssetPatcher.get_data("limitbursts"))
	game_data_materia = _sanitize_floats_to_ints(AssetPatcher.get_data("materia"))
	game_data_equipment_icons = _sanitize_floats_to_ints(AssetPatcher.get_data("equipment-icons"))
	game_data_monsters = _sanitize_floats_to_ints(AssetPatcher.get_data("monsters"))
	_load_opcode_schemas()

func _load_opcode_schemas() -> void:
	opcode_schemas_ready = false
	opcode_schema_error = ""
	opcode_skill_schema = _load_opcode_schema_file(OPCODE_SKILL_SCHEMA_PATH, "skill")
	opcode_passive_schema = _load_opcode_schema_file(OPCODE_PASSIVE_SCHEMA_PATH, "passive")

	if opcode_schema_error != "":
		return

	opcode_schemas_ready = true

func _load_opcode_schema_file(schema_path: String, schema_name: String) -> Dictionary:
	if not FileAccess.file_exists(schema_path):
		_record_opcode_schema_error("CRITICAL ERROR: Missing %s opcode schema at %s" % [schema_name, schema_path])
		return {}

	var json_as_text: String = FileAccess.get_file_as_string(schema_path)
	if json_as_text.strip_edges() == "":
		_record_opcode_schema_error("CRITICAL ERROR: Empty %s opcode schema at %s" % [schema_name, schema_path])
		return {}

	var parsed: Variant = JSON.parse_string(json_as_text)
	if parsed == null:
		_record_opcode_schema_error("CRITICAL ERROR: Invalid JSON in %s opcode schema at %s" % [schema_name, schema_path])
		return {}

	if not parsed is Dictionary:
		_record_opcode_schema_error("CRITICAL ERROR: %s opcode schema must parse as Dictionary at %s" % [schema_name, schema_path])
		return {}

	return parsed as Dictionary

func _record_opcode_schema_error(error_message: String) -> void:
	if opcode_schema_error == "":
		opcode_schema_error = error_message
	push_error(error_message)

func _ensure_opcode_schemas_ready(caller_name: String) -> bool:
	if opcode_schemas_ready:
		return true

	var details: String = opcode_schema_error if opcode_schema_error != "" else "CRITICAL ERROR: Opcode schemas not loaded."
	push_error("DataManager: %s cannot parse opcodes. %s" % [caller_name, details])
	return false

func parse_passive_effects(skill_data: Dictionary) -> Dictionary:
	if not _ensure_opcode_schemas_ready("parse_passive_effects"):
		return {"effects": []}

	return OpcodeParser.parse_passive(skill_data, opcode_passive_schema)

func parse_skill_effects(skill_data: Dictionary) -> Dictionary:
	if not _ensure_opcode_schemas_ready("parse_skill_effects"):
		return {
			"element_inflict": skill_data.get("element_inflict", []),
			"effects": []
		}

	return OpcodeParser.parse_skill(skill_data, opcode_skill_schema)

func _find_item_ability_id(effects_raw: Array) -> String:
	for effect in effects_raw:
		if effect.size() < 4:
			continue
		if int(effect[2]) != 71:
			continue

		var payload: Variant = effect[3]
		if typeof(payload) != TYPE_ARRAY or payload.size() == 0:
			continue

		return str(payload[0])

	return ""

func _get_active_skill_record(skill_id: String) -> Dictionary:
	var skill_data: Dictionary = game_data_skills_magic.get(skill_id, {})
	if not skill_data.is_empty():
		return skill_data

	return game_data_skills_ability.get(skill_id, {})

func _build_targeting_metadata(parsed_data: Dictionary) -> Dictionary:
	var metadata: Dictionary = {
		"needs_ally_selection": false,
		"targets_allies": false,
		"targets_enemies": false,
		"targets_self": false,
		"has_aoe": false
	}

	for effect in parsed_data.get("effects", []):
		var target_area: int = int(effect.get("target_area", 1))
		var target_type: int = int(effect.get("target_type", 1))

		if target_area == 2:
			metadata["has_aoe"] = true

		if target_type == 3:
			metadata["targets_self"] = true
		elif target_type == 1:
			metadata["targets_enemies"] = true
		elif target_type in [2, 6]:
			metadata["targets_allies"] = true
			if target_area == 1:
				metadata["needs_ally_selection"] = true

	return metadata

func resolve_combat_skill(skill_id: String) -> Dictionary:
	var resolved_skill: Dictionary = _get_active_skill_record(skill_id)
	if resolved_skill.is_empty():
		push_error("DataManager: Combat skill not found: %s" % skill_id)
		return {}

	var parsed_data: Dictionary = parse_skill_effects(resolved_skill)
	return {
		"source_type": "skill",
		"source_id": skill_id,
		"resolved_action_id": skill_id,
		"resolved_action_name": resolved_skill.get("name", ""),
		"resolved_action_data": resolved_skill,
		"parsed_data": parsed_data,
		"targeting": _build_targeting_metadata(parsed_data)
	}

func get_limitburst_max_gauge(limitburst_id: String) -> int:
	var default_max_gauge: int = 100
	if limitburst_id == "":
		return default_max_gauge

	var limitburst_data: Dictionary = game_data_limitbursts.get(limitburst_id, {})
	if limitburst_data.is_empty():
		push_error("DataManager: Limit burst data not found: %s" % limitburst_id)
		return default_max_gauge

	var levels: Variant = limitburst_data.get("levels", [])
	if not (levels is Array) or (levels as Array).is_empty():
		push_error("DataManager: Limit burst levels missing or invalid for id: %s" % limitburst_id)
		return default_max_gauge

	var first_level: Variant = (levels as Array)[0]
	if not (first_level is Array) or (first_level as Array).is_empty():
		push_error("DataManager: Limit burst first level invalid for id: %s" % limitburst_id)
		return default_max_gauge

	var gauge_value: Variant = (first_level as Array)[0]
	if typeof(gauge_value) not in [TYPE_INT, TYPE_FLOAT]:
		push_error("DataManager: Limit burst gauge value invalid for id: %s" % limitburst_id)
		return default_max_gauge

	return max(1, int(gauge_value))

func resolve_combat_limitburst(limitburst_id: String) -> Dictionary:
	var resolved_limitburst: Dictionary = game_data_limitbursts.get(limitburst_id, {})
	if resolved_limitburst.is_empty():
		push_error("DataManager: Combat limit burst not found: %s" % limitburst_id)
		return {}

	var parsed_data: Dictionary = parse_skill_effects(resolved_limitburst)
	return {
		"source_type": "limitburst",
		"source_id": limitburst_id,
		"resolved_action_id": limitburst_id,
		"resolved_action_name": resolved_limitburst.get("name", ""),
		"resolved_action_data": resolved_limitburst,
		"parsed_data": parsed_data,
		"targeting": _build_targeting_metadata(parsed_data)
	}

func resolve_combat_item(item_id: String) -> Dictionary:
	var item_data: Dictionary = game_data_items.get(item_id, {})
	if item_data.is_empty():
		push_error("DataManager: Combat item not found: %s" % item_id)
		return {}

	var resolved_ability_id: String = _find_item_ability_id(item_data.get("effects_raw", []))
	if resolved_ability_id == "":
		push_error("DataManager: Combat item missing opcode 71 ability reference: %s" % item_id)
		return {}

	var resolved_action_data: Dictionary = game_data_skills_ability.get(resolved_ability_id, {})
	if resolved_action_data.is_empty():
		push_error("DataManager: Combat item ability not found: %s -> %s" % [item_id, resolved_ability_id])
		return {}

	var parsed_data: Dictionary = parse_skill_effects(resolved_action_data)
	return {
		"source_type": "item",
		"source_id": item_id,
		"source_item_data": item_data,
		"resolved_action_id": resolved_ability_id,
		"resolved_action_name": resolved_action_data.get("name", item_data.get("name", "")),
		"resolved_action_data": resolved_action_data,
		"parsed_data": parsed_data,
		"targeting": _build_targeting_metadata(parsed_data),
		"original_item_id": item_id
	}

func _update_wallet_data(wallet: Dictionary) -> void:
	assert(wallet.has("gil"), "CRITICAL ERROR: wallet is missing gil!")
	if not wallet.has("gil"): push_error("CRITICAL ERROR: wallet is missing gil!")
	gil = int(wallet["gil"])
	assert(wallet.has("lapis"), "CRITICAL ERROR: wallet is missing lapis!")
	if not wallet.has("lapis"): push_error("CRITICAL ERROR: wallet is missing lapis!")
	lapis = int(wallet["lapis"])
	currency_updated.emit(gil, lapis)

func add_rank_xp(xp_to_add: int) -> void:
	var result: Dictionary = await server_connection.add_rank_xp_async(xp_to_add)
	if not result.is_empty():
		assert(result.has("rank"), "CRITICAL ERROR: result is missing rank!")
		if not result.has("rank"): push_error("CRITICAL ERROR: result is missing rank!")
		current_rank = int(result["rank"])
		assert(result.has("xp"), "CRITICAL ERROR: result is missing xp!")
		if not result.has("xp"): push_error("CRITICAL ERROR: result is missing xp!")
		current_xp = int(result["xp"])
		assert(result.has("next_rank_xp"), "CRITICAL ERROR: result is missing next_rank_xp!")
		if not result.has("next_rank_xp"): push_error("CRITICAL ERROR: result is missing next_rank_xp!")
		next_rank_xp = int(result["next_rank_xp"])
		assert(result.has("current_nrg"), "CRITICAL ERROR: result is missing current_nrg!")
		if not result.has("current_nrg"): push_error("CRITICAL ERROR: result is missing current_nrg!")
		current_nrg = int(result["current_nrg"])
		assert(result.has("max_nrg"), "CRITICAL ERROR: result is missing max_nrg!")
		if not result.has("max_nrg"): push_error("CRITICAL ERROR: result is missing max_nrg!")
		max_nrg = int(result["max_nrg"])
		assert(result.has("nrg_regen_rate_seconds"), "CRITICAL ERROR: result is missing nrg_regen_rate_seconds!")
		if not result.has("nrg_regen_rate_seconds"): push_error("CRITICAL ERROR: result is missing nrg_regen_rate_seconds!")
		nrg_regen_rate_seconds = int(result["nrg_regen_rate_seconds"])
		assert(result.has("seconds_until_next_nrg"), "CRITICAL ERROR: result is missing seconds_until_next_nrg!")
		if not result.has("seconds_until_next_nrg"): push_error("CRITICAL ERROR: result is missing seconds_until_next_nrg!")
		seconds_until_next_nrg = float(result["seconds_until_next_nrg"])
		last_entered_mission_id = str(result.get("last_entered_mission_id", last_entered_mission_id))
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
			assert(owned_items.has("equipment"), "CRITICAL ERROR: owned_items is missing equipment!")
			if not owned_items.has("equipment"): push_error("CRITICAL ERROR: owned_items is missing equipment!")
			if typeof(owned_items["equipment"]) == TYPE_ARRAY:
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
		purchase_failed.emit(result.get("error", "ERR_MISSING_SERVER_ERROR_MSG"))

func request_start_mission(mission_id: String) -> Dictionary:
	var result: Dictionary = await server_connection.start_mission_async(mission_id)
	if result.get("success", false) == true:
		last_entered_mission_id = mission_id
		await _update_last_played_dungeon_from_mission(mission_id)
	return result

func load_mission_progress() -> void:
	var progress_payload: Dictionary = await server_connection.get_mission_progress_async()
	var payload_cleared_missions: Variant = progress_payload.get("cleared_missions", {})

	if payload_cleared_missions is Dictionary:
		cleared_missions = payload_cleared_missions
	else:
		cleared_missions = {}

	latest_cleared_mission_id = _get_latest_cleared_mission_id_from_progress(cleared_missions)

	if latest_cleared_mission_id != "":
		await _update_last_played_dungeon_from_mission(latest_cleared_mission_id)

	mission_progress_loaded.emit(latest_cleared_mission_id)

func get_latest_cleared_map_selection() -> Dictionary:
	if latest_cleared_mission_id == "":
		return {}
	return await get_map_selection_for_mission(latest_cleared_mission_id)

func get_map_selection_for_mission(mission_id: String) -> Dictionary:
	var mission_data: Dictionary = await _get_or_load_mission_data(mission_id)
	if mission_data.is_empty():
		return {}

	var dungeon_id: String = str(int(mission_data.get("dungeon_id", "")))
	if dungeon_id == "":
		return {}

	var map_location: Dictionary = _find_dungeon_location_in_worlds(dungeon_id)
	if map_location.is_empty():
		return {}

	map_location["mission_id"] = mission_id
	map_location["dungeon_id"] = dungeon_id
	return map_location

func _update_last_played_dungeon_from_mission(mission_id: String) -> void:
	if mission_id == "":
		last_played_dungeon_name = ""
		return

	var mission_data: Dictionary = await _get_or_load_mission_data(mission_id)

	if mission_data.is_empty():
		return

	var dungeon_id: String = str(int(mission_data.get("dungeon_id", "")))
	if dungeon_id == "":
		return

	var dungeon_data: Dictionary = game_data_dungeons.get(dungeon_id, {})
	if dungeon_data.is_empty():
		return

	if dungeon_data.has("names") and dungeon_data["names"] is Array and dungeon_data["names"].size() > 0:
		var dungeon_name: String = str(dungeon_data["names"][0])
		last_played_dungeon_name = dungeon_name.replace(" ", "_")

func _get_or_load_mission_data(mission_id: String) -> Dictionary:
	var mission_key: String = str(mission_id)
	var mission_data: Dictionary = game_data_missions.get(mission_key, {})

	if mission_data.is_empty():
		var fetched_missions: Dictionary = await server_connection.get_dungeon_missions_async([mission_key])
		if fetched_missions.has(mission_key):
			mission_data = fetched_missions[mission_key]
			game_data_missions[mission_key] = mission_data

	return mission_data

func _get_latest_cleared_mission_id_from_progress(progress: Dictionary) -> String:
	var latest_numeric_id: int = -1

	for mission_key in progress.keys():
		var mission_key_str: String = str(mission_key)
		var progress_entry: Variant = progress[mission_key]
		if progress_entry is Dictionary and progress_entry.has("cleared") and progress_entry["cleared"] == false:
			continue

		var numeric_id: int = _extract_mission_numeric_id(mission_key_str)
		if numeric_id > latest_numeric_id:
			latest_numeric_id = numeric_id

	if latest_numeric_id < 0:
		return ""

	return str(latest_numeric_id)

func _extract_mission_numeric_id(mission_key: String) -> int:
	var numeric_str: String = mission_key
	if numeric_str.begins_with("mission_"):
		numeric_str = numeric_str.substr(8)

	if not numeric_str.is_valid_int():
		return -1

	return int(numeric_str)

func _find_dungeon_location_in_worlds(dungeon_id: String) -> Dictionary:
	for world_id in game_data_worlds.keys():
		var world_data: Dictionary = game_data_worlds.get(world_id, {})
		var regions: Dictionary = world_data.get("regions", {})
		for region_id in regions.keys():
			var region_data: Dictionary = regions.get(region_id, {})
			var subregions: Dictionary = region_data.get("subregions", {})
			for subregion_id in subregions.keys():
				var subregion_data: Dictionary = subregions.get(subregion_id, {})
				var dungeons: Variant = subregion_data.get("dungeons", [])
				if _subregion_contains_dungeon(dungeons, dungeon_id):
					return {
						"world_id": str(world_id),
						"region_id": str(region_id),
						"subregion_id": str(subregion_id)
					}

	return {}

func _subregion_contains_dungeon(dungeons: Variant, dungeon_id: String) -> bool:
	if dungeons is Dictionary:
		for candidate_id in dungeons.keys():
			if str(candidate_id) == dungeon_id:
				return true
		return false

	if dungeons is Array:
		for candidate_id in dungeons:
			if str(candidate_id) == dungeon_id:
				return true
		return false

	if dungeons is String:
		return str(dungeons) == dungeon_id

	return false

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
	summoned_units = _hydrate_owned_units(summoned_units)
	owned_units_ids.append_array(summoned_units)
	units_updated.emit(owned_units_ids)
	return summoned_units

func add_unit_xp(instance_id: String, xp_amount: int) -> Dictionary:
	var result: Dictionary = await server_connection.add_unit_xp_async(instance_id, xp_amount)
	if not result.has("error"):
		owned_units_ids = await server_connection.read_player_units_async()
		owned_units_ids = _hydrate_owned_units(owned_units_ids)
		units_updated.emit(owned_units_ids)
	return result

func awaken_unit(instance_id: String) -> Dictionary:
	var result: Dictionary = await server_connection.awaken_unit_async(instance_id)
	if not result.has("error"):
		owned_units_ids = await server_connection.read_player_units_async()
		owned_units_ids = _hydrate_owned_units(owned_units_ids)
		units_updated.emit(owned_units_ids)
	return result

func request_equip_item(instance_id: String, slot_id: String, item_id: String) -> void:
	if item_id != "" and slot_id in ["r_hand", "l_hand"]:
		var item_data_dict: Dictionary = {}
		assert(owned_items.has("equipment"), "CRITICAL ERROR: owned_items is missing equipment!")
		if not owned_items.has("equipment"): push_error("CRITICAL ERROR: owned_items is missing equipment!")
		var equipment_list = owned_items["equipment"] if owned_items.has("equipment") else []
		for item in equipment_list:
			if item is Dictionary:
				assert(item.has("instance_id"), "CRITICAL ERROR: item is missing instance_id!")
				if not item.has("instance_id"): push_error("CRITICAL ERROR: item is missing instance_id!")
				if item["instance_id"] == item_id:
					assert(item.has("template_id"), "CRITICAL ERROR: item is missing template_id!")
					if not item.has("template_id"): push_error("CRITICAL ERROR: item is missing template_id!")
					var template_id: String = item["template_id"]
					if game_data_equipment.has(template_id):
						item_data_dict = game_data_equipment[template_id]
					break

		if item_data_dict.get("is_twohanded", false):
			var other_hand: String = "l_hand" if slot_id == "r_hand" else "r_hand"
			await server_connection.equip_item_async(instance_id, other_hand, "")

	var result: Dictionary = await server_connection.equip_item_async(instance_id, slot_id, item_id)
	if not result.has("error"):
		owned_units_ids = await server_connection.read_player_units_async()
		owned_units_ids = _hydrate_owned_units(owned_units_ids)
		units_updated.emit(owned_units_ids)
		equip_successful.emit()
	else:
		equip_failed.emit(result.get("error", "ERR_MISSING_SERVER_ERROR_MSG"))
		
func _hydrate_owned_units(units: Array) -> Array:
	var hydrated_units: Array = []
	for unit_instance in units:
		if typeof(unit_instance) != TYPE_DICTIONARY:
			hydrated_units.append(unit_instance)
			continue

		var hydrated_unit: Dictionary = {}

		# 1. Base Template Data
		var unit_id = str(unit_instance.get("unit_id", ""))
		var template_data = game_data_units.get(unit_id, {})
		hydrated_unit.merge(template_data)

		# 2. Rarity Entry Data
		var rarity = int(unit_instance.get("current_rarity", 1))
		var entries = template_data.get("entries", {})
		var rarity_entry = {}

		if entries.has(str(unit_id)):
			rarity_entry = entries[str(unit_id)]
		elif entries.has(str(rarity)):
			rarity_entry = entries[str(rarity)]

		for key in entries.keys():
			if entries[key].has("rarity") and int(entries[key]["rarity"]) == rarity:
				rarity_entry = entries[key]
				break

		hydrated_unit.merge(rarity_entry, true)

		# 3. Instance Data
		hydrated_unit.merge(unit_instance, true)

		# 4. Calculate Final Stats
		hydrated_unit["final_stats"] = StatCalculator.calculate_final_stats(hydrated_unit)

		hydrated_units.append(hydrated_unit)

	return hydrated_units

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

func request_finish_mission(win_status: bool, mission_id: String, used_items: Dictionary = {}, challenge_results: Array = []) -> Dictionary:
	var result: Dictionary = await server_connection.finish_mission_async(win_status, used_items, challenge_results)
	if not result.has("error") and result.get("success", false) == true:
		if result.has("rewards"):
			var rewards = result.rewards
			if rewards.has("stats"):
				var stats = rewards.stats
				if stats.has("rank"): current_rank = int(stats["rank"])
				if stats.has("xp"): current_xp = int(stats["xp"])
				if stats.has("next_rank_xp"): next_rank_xp = int(stats["next_rank_xp"])
				if stats.has("current_nrg"): current_nrg = int(stats["current_nrg"])
				if stats.has("max_nrg"): max_nrg = int(stats["max_nrg"])
				if stats.has("nrg_regen_rate_seconds"): nrg_regen_rate_seconds = float(stats["nrg_regen_rate_seconds"])
				if stats.has("seconds_until_next_nrg"): seconds_until_next_nrg = float(stats["seconds_until_next_nrg"])
				if stats.has("last_entered_mission_id"):
					last_entered_mission_id = str(stats["last_entered_mission_id"])
					await _update_last_played_dungeon_from_mission(last_entered_mission_id)
				rank_updated.emit(current_rank, current_xp, next_rank_xp)
				nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
			if rewards.has("wallet"):
				var wallet = JSON.parse_string(rewards.wallet) if rewards.wallet is String else rewards.wallet
				_update_wallet_data(wallet)

		if win_status:
			var rewards_text: String = ""
			var mission_data: Dictionary = game_data_missions.get(mission_id, {})
			if mission_data.has("gil"):
				rewards_text += "Gil +%s\n" % str(int(mission_data["gil"]))
			if mission_data.has("exp"):
				rewards_text += "Rank EXP +%s\n" % str(int(mission_data["exp"]))
			mission_completed.emit(rewards_text)
	else:
		if win_status:
			mission_failed.emit(str(result.get("error", "Unknown error finishing mission")))
	
	# Update items since they might have been deducted
	#request_player_items()
	
	return result

func request_dungeon_missions(mission_ids: Array) -> void:
	var detailed_missions: Dictionary = await server_connection.get_dungeon_missions_async(mission_ids)
	for mission_id in mission_ids:
		assert(detailed_missions.has(str(mission_id)), "CRITICAL ERROR: detailed_missions is missing mission_id: " + str(mission_id))
		if not detailed_missions.has(str(mission_id)): push_error("CRITICAL ERROR: detailed_missions is missing mission_id: " + str(mission_id))
		var mission_data = detailed_missions[str(mission_id)] if detailed_missions.has(str(mission_id)) else {}
		if not mission_data.is_empty():
			game_data_missions[str(mission_id)] = mission_data # Cache it
	dungeon_missions_ready.emit(mission_ids)

func get_equipment_template_id(instance_id: String) -> String:
	assert(owned_items.has("equipment"), "CRITICAL ERROR: owned_items is missing equipment!")
	if not owned_items.has("equipment"): push_error("CRITICAL ERROR: owned_items is missing equipment!")
	var equipment_list = owned_items["equipment"] if owned_items.has("equipment") else []
	for item in equipment_list:
		if not item is Dictionary: continue
		assert(item.has("instance_id"), "CRITICAL ERROR: item is missing instance_id!")
		if not item.has("instance_id"): push_error("CRITICAL ERROR: item is missing instance_id!")
		if item["instance_id"] == instance_id:
			assert(item.has("template_id"), "CRITICAL ERROR: item is missing template_id!")
			if not item.has("template_id"): push_error("CRITICAL ERROR: item is missing template_id!")
			return item["template_id"]
	return ""

func get_available_equipment_for_slot(slot_id: String, allowed_equips: Array) -> Array:
	var available_items: Array = []
	assert(owned_items.has("equipment"), "CRITICAL ERROR: owned_items is missing equipment!")
	if not owned_items.has("equipment"): push_error("CRITICAL ERROR: owned_items is missing equipment!")
	var equipment_list = owned_items["equipment"] if owned_items.has("equipment") else []
	for item in equipment_list:
		if not item is Dictionary: continue
		assert(item.has("instance_id"), "CRITICAL ERROR: item is missing instance_id!")
		if not item.has("instance_id"): push_error("CRITICAL ERROR: item is missing instance_id!")
		var instance_id: String = item["instance_id"]

		assert(item.has("template_id"), "CRITICAL ERROR: item is missing template_id!")
		if not item.has("template_id"): push_error("CRITICAL ERROR: item is missing template_id!")
		var template_id: String = item["template_id"]

		assert(game_data_equipment.has(template_id), "CRITICAL ERROR: game_data_equipment is missing template_id: " + template_id)
		if not game_data_equipment.has(template_id): push_error("CRITICAL ERROR: game_data_equipment is missing template_id: " + template_id)
		var item_data: Variant = game_data_equipment[template_id] if game_data_equipment.has(template_id) else null
		if not item_data: continue

		var item_data_dict: Dictionary = item_data as Dictionary

		assert(item_data_dict.has("type_id"), "CRITICAL ERROR: item_data_dict is missing type_id!")
		if not item_data_dict.has("type_id"): push_error("CRITICAL ERROR: item_data_dict is missing type_id!")
		var item_type_id: int = item_data_dict["type_id"]

		var is_valid_slot: bool = false

		assert(item_data_dict.has("slot"), "CRITICAL ERROR: item_data_dict is missing slot!")
		if not item_data_dict.has("slot"): push_error("CRITICAL ERROR: item_data_dict is missing slot!")
		var item_slot: String = item_data_dict["slot"]
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
