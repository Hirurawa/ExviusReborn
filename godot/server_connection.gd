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

func write_player_stats_async(level: int, xp: int) -> int:
	if _session == null or _session.is_expired():
		return ERR_UNAUTHORIZED

	var data := {
		"level": level,
		"xp": xp
	}

	var json_data := JSON.stringify(data)

	var object := NakamaWriteStorageObject.new("stats", "player_stats", 1, 1, json_data, "")
	var result = await(_client.write_storage_objects_async(_session, [object]))

	if result.is_exception():
		return result.get_exception().status_code

	return OK

func read_player_stats_async() -> Dictionary:
	var default_stats := {"level": 1, "xp": 0}

	if _session == null or _session.is_expired():
		return default_stats

	var object_id := NakamaStorageObjectId.new("stats", "player_stats", _session.user_id)
	var result: NakamaAPI.ApiStorageObjects = await(_client.read_storage_objects_async(_session, [object_id]))

	if result.is_exception():
		return default_stats

	if result.objects.is_empty():
		return default_stats

	var obj: NakamaAPI.ApiStorageObject = result.objects[0]
	var dict = JSON.parse_string(obj.value)

	if dict and dict is Dictionary:
		return dict

	return default_stats
