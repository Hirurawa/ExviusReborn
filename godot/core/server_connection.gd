extends Node

const KEY := "nakama_godot"

var _session: NakamaSession

var _client := Nakama.create_client(KEY, "127.0.0.1", 7350, "http")

func authenticate_async(email: String, password: String) -> int:
	var result := OK
	
	var new_session: NakamaSession = await(_client.authenticate_email_async(email, password, "", false))

	if not new_session.is_exception():
		_session = new_session
	else:
		result = new_session.get_exception().status_code

	return result

func logout() -> void:
	_session = null

func get_account_async():
	if _session == null or _session.is_expired():
		return null

	var account = await(_client.get_account_async(_session))
	if account.is_exception():
		return null

	return account as NakamaAPI.ApiAccount

func update_account_async(username: String) -> int:
	if _session == null or _session.is_expired():
		return ERR_UNAUTHORIZED

	var result = await(_client.update_account_async(_session, username))

	if result.is_exception():
		return result.get_exception().status_code

	return OK

func register_async(email: String, password: String, username: String) -> int:
	var result := OK

	var new_session: NakamaSession = await(_client.authenticate_email_async(email, password, username, true))
	
	if not new_session.is_exception():
		_session = new_session
	else:
		result = new_session.get_exception().status_code
	
	return result

func add_friends_async(username: String) -> int:
	if _session == null or _session.is_expired():
		return ERR_UNAUTHORIZED

	var usernames: PackedStringArray = [username]
	var result = await(_client.add_friends_async(_session, [], usernames))

	if result.is_exception():
		return result.get_exception().status_code

	return OK

func delete_friends_async(username: String) -> int:
	if _session == null or _session.is_expired():
		return ERR_UNAUTHORIZED

	var usernames: PackedStringArray = [username]
	var result = await(_client.delete_friends_async(_session, [], usernames))

	if result.is_exception():
		return result.get_exception().status_code

	return OK

func list_friends_async() -> NakamaAPI.ApiFriendList:
	if _session == null or _session.is_expired():
		return null

	var result = await(_client.list_friends_async(_session, null, 100))

	if result.is_exception():
		return null

	return result as NakamaAPI.ApiFriendList

func add_rank_xp_async(xp_amount: int) -> Dictionary:
	if _session == null or _session.is_expired():
		return {}

	var payload = JSON.stringify({
		"xp_amount": xp_amount
	})

	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "add_rank_xp", payload)

	if result.is_exception():
		push_error("Failed to add rank xp: %s" % result.get_exception().message)
		return {}

	var dict = JSON.parse_string(result.payload)
	if dict and dict is Dictionary:
		return dict

	return {}

func read_player_stats_async() -> Dictionary:
	var default_stats := {"rank": 1, "xp": 0, "energy": 41, "max_energy": 41}

	if _session == null or _session.is_expired():
		return default_stats

	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "get_player_stats", "{}")

	if result.is_exception():
		push_error("Failed to read player stats: %s" % result.get_exception().message)
		return default_stats

	var dict = JSON.parse_string(result.payload)

	if dict and dict is Dictionary:
		return dict

	return default_stats

func write_player_units_async(units: Array) -> int:
	if _session == null or _session.is_expired():
		return ERR_UNAUTHORIZED

	var data := {
		"units": units
	}

	var json_data := JSON.stringify(data)

	var object := NakamaWriteStorageObject.new("units", "player_units", 1, 1, json_data, "")
	var result = await(_client.write_storage_objects_async(_session, [object]))

	if result.is_exception():
		return result.get_exception().status_code

	return OK

func read_player_units_async() -> Array:
	if _session == null or _session.is_expired():
		return []

	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "get_player_units", "{}")

	if result.is_exception():
		return []

	var dict = JSON.parse_string(result.payload)

	if dict and dict is Dictionary and dict.has("units") and dict["units"] is Array:
		return dict["units"]

	return []

func get_game_data_async(data_type: String = "core") -> Dictionary:
	if _session == null or _session.is_expired():
		return {}

	var payload = JSON.stringify({"type": data_type})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "get_game_data", payload)

	if result.is_exception():
		push_error("Failed to get game data (%s): %s" % [data_type, result.get_exception().message])
		return {}

	var dict = JSON.parse_string(result.payload)
	if dict and dict is Dictionary:
		return dict

	return {}

func get_dungeon_missions_async(mission_ids: Array) -> Dictionary:
	if _session == null or _session.is_expired():
		return {}

	var payload = JSON.stringify({"mission_ids": mission_ids})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "get_dungeon_missions", payload)

	if result.is_exception():
		push_error("Failed to get dungeon missions: %s" % result.get_exception().message)
		return {}

	var dict = JSON.parse_string(result.payload)
	if dict and dict is Dictionary and dict.has("missions"):
		return dict.get("missions", {})

	return {}

func summon_units_async(amount: int) -> Array:
	if _session == null or _session.is_expired():
		return []

	var payload = JSON.stringify({"amount": amount})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "summon_units", payload)

	if result.is_exception():
		push_error("Failed to summon units: %s" % result.get_exception().message)
		return []

	var dict = JSON.parse_string(result.payload)
	if dict and dict is Dictionary and dict.has("summoned") and dict["summoned"] is Array:
		return dict["summoned"]

	return []

func add_unit_xp_async(instance_id: String, xp_amount: int) -> Dictionary:
	if _session == null or _session.is_expired():
		return {}

	var payload = JSON.stringify({
		"instance_id": instance_id,
		"xp_amount": xp_amount
	})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "add_unit_xp", payload)

	if result.is_exception():
		push_error("Failed to add unit xp: %s" % result.get_exception().message)
		return {}

	var dict = JSON.parse_string(result.payload)
	if dict and dict is Dictionary:
		return dict

	return {}

func awaken_unit_async(instance_id: String) -> Dictionary:
	if _session == null or _session.is_expired():
		return {}

	var payload = JSON.stringify({"instance_id": instance_id})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "awaken_unit", payload)

	if result.is_exception():
		push_error("Failed to awaken unit: %s" % result.get_exception().message)
		return {}

	var dict = JSON.parse_string(result.payload)
	if dict and dict is Dictionary:
		return dict

	return {}

func get_parties_async() -> Array:
	if not _session:
		return []

	var rpc_id = "get_parties"
	var payload = "{}"
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, rpc_id, payload)

	if result.is_exception():
		push_error("get_parties error: %s" % result.get_exception().message)
		return []

	var data = JSON.parse_string(result.payload)
	if data and data.has("parties"):
		return data.parties
	return []

func save_parties_async(parties: Array) -> Dictionary:
	if not _session:
		return {"error": "Not authenticated"}

	var rpc_id = "save_parties"
	var payload = JSON.stringify({"parties": parties})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, rpc_id, payload)

	if result.is_exception():
		var err_msg = result.get_exception().message
		push_error("save_parties error: %s" % err_msg)
		return {"error": err_msg}

	var data = JSON.parse_string(result.payload)
	if data:
		return data
	return {"error": "Failed to parse response"}

func read_player_items_async() -> Dictionary:
	if _session == null or _session.is_expired():
		return {"stackables": {}, "equipment": []}

	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "get_player_items", "{}")

	if result.is_exception():
		return {"stackables": {}, "equipment": []}

	var dict = JSON.parse_string(result.payload)

	if dict and dict is Dictionary:
		return dict

	return {"stackables": {}, "equipment": []}

func add_item_async(item_id: String, quantity: int = 1) -> Dictionary:
	if _session == null or _session.is_expired():
		return {}

	var payload = JSON.stringify({
		"item_id": item_id,
		"quantity": quantity
	})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "add_item", payload)

	if result.is_exception():
		push_error("Failed to add item: %s" % result.get_exception().message)
		return {}

	var dict = JSON.parse_string(result.payload)
	if dict and dict is Dictionary:
		return dict

	return {}

func add_currency_async(gil: int, lapis: int) -> Dictionary:
	if _session == null or _session.is_expired():
		return {}

	var payload = JSON.stringify({
		"gil": gil,
		"lapis": lapis
	})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "add_currency", payload)

	if result.is_exception():
		push_error("Failed to add currency: %s" % result.get_exception().message)
		return {}

	var dict = JSON.parse_string(result.payload)
	if dict and dict is Dictionary:
		return dict

	return {}

func buy_item_async(item_id: String, quantity: int = 1) -> Dictionary:
	if _session == null or _session.is_expired():
		return {}

	var payload = JSON.stringify({
		"item_id": item_id,
		"quantity": quantity
	})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "buy_item", payload)

	if result.is_exception():
		push_error("Failed to buy item: %s" % result.get_exception().message)
		return {}

	var dict = JSON.parse_string(result.payload)
	if dict and dict is Dictionary:
		return dict

	return {}

func start_mission_async(mission_id: String) -> Dictionary:
	if _session == null or _session.is_expired():
		return {"success": false, "error": "Not authenticated"}

	var payload = JSON.stringify({
		"mission_id": mission_id
	})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "start_mission", payload)

	if result.is_exception():
		push_error("Failed to start mission: %s" % result.get_exception().message)
		return {"success": false, "error": result.get_exception().message}

	var dict = JSON.parse_string(result.payload)
	if dict and dict is Dictionary:
		return dict

	return {"success": false, "error": "Invalid response"}

func finish_mission_async(win_status: bool, used_items: Dictionary = {}) -> Dictionary:
	if _session == null or _session.is_expired():
		return {"success": false, "error": "Not authenticated"}

	var payload = JSON.stringify({
		"win_status": win_status,
		"used_items": used_items
	})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "finish_mission", payload)

	if result.is_exception():
		push_error("Failed to finish mission: %s" % result.get_exception().message)
		return {"success": false, "error": result.get_exception().message}

	var dict = JSON.parse_string(result.payload)
	if dict and dict is Dictionary:
		return dict

	return {"success": false, "error": "Invalid response"}

func equip_item_async(unit_instance_id: String, slot: String, item_instance_id: String) -> Dictionary:
	var payload = JSON.stringify({"unit_instance_id": unit_instance_id, "slot": slot, "item_instance_id": item_instance_id})
	var result: NakamaAPI.ApiRpc = await _client.rpc_async(_session, "equip_item", payload)
	if result.is_exception():
		var ex = result.get_exception()
		return {"error": ex.message}
	
	var json = JSON.new()
	var parse_result = json.parse(result.payload)
	if parse_result == OK:
		return json.get_data()
	else:
		return {"error": "Failed to parse JSON response"}
