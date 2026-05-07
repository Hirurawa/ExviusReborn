extends Node

signal patch_progress(file_name: String, status: String)
signal patch_complete

var files_to_patch: Array[String] = ["units", "items", "worlds", "dungeons", "missions", "skills_ability", "skills_magic", "skills_passive", "equipment", "limitbursts", "materia", "equipment-icons", "monsters", "summons", "summons_boards", "summons_exp_patterns", "summons_stat_patterns"]
var current_patch_index: int = 0
const BUNDLED_STATIC_VERSION: String = "bundled-v1"
const BUNDLED_STATIC_DIRS: Array[String] = ["res://assets/static_data", "res://assets"]
var prefer_bundled_static_data: bool = true

var cached_data: Dictionary = {}
var _http_request: HTTPRequest
var server_connection: Node

func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	
	# Create data dir if it doesn't exist
	var dir: DirAccess = DirAccess.open("user://")
	if not dir.dir_exists("data"):
		dir.make_dir("data")

func start_patching() -> void:
	if server_connection == null:
		push_error("AssetPatcher: Nakama ServerConnection not found.")
		for file_type in files_to_patch:
			_load_with_fallback(file_type)
		patch_complete.emit()
		return
	
	current_patch_index = 0
	_patch_next_file()

func _patch_next_file() -> void:
	if current_patch_index >= files_to_patch.size():
		patch_complete.emit()
		return
		
	var file_type: String = files_to_patch[current_patch_index]
	patch_progress.emit(file_type, "Checking version...")

	# Local-first mode avoids RPC/HTTP failures when bundled static JSON is present.
	if prefer_bundled_static_data and _load_from_bundled_static(file_type):
		current_patch_index += 1
		call_deferred("_patch_next_file")
		return
	
	if not server_connection.get("_session"):
		push_error("AssetPatcher: Nakama session is invalid.")
		_load_with_fallback(file_type)
		current_patch_index += 1
		call_deferred("_patch_next_file")
		return
		
	var rpc_payload: String = JSON.stringify({"type": file_type})
	var result: NakamaAsyncResult = await server_connection.get("_client").rpc_async(server_connection.get("_session"), "get_data_version", rpc_payload)
	
	if result.is_exception():
		push_error("Failed to get data version for %s: %s" % [file_type, result.get_exception().message])
		_load_with_fallback(file_type)
		current_patch_index += 1
		call_deferred("_patch_next_file")
		return
		
	var dict: Variant = JSON.parse_string(result.payload)
	if not dict or not dict is Dictionary or not dict.has("version"):
		push_error("Invalid response for %s version: %s" % [file_type, result.payload])
		_load_with_fallback(file_type)
		current_patch_index += 1
		call_deferred("_patch_next_file")
		return
		
	var server_version: String = dict["version"]
	var download_url: String = dict["download_url"]
	
	var local_version: String = _get_local_version(file_type)
	
	if local_version == server_version and _cache_exists(file_type):
		patch_progress.emit(file_type, "Up to date")
		_load_from_cache(file_type)
		current_patch_index += 1
		call_deferred("_patch_next_file")
	else:
		patch_progress.emit(file_type, "Downloading...")
		_download_file(file_type, download_url, server_version)

func _download_file(file_type: String, url: String, new_version: String) -> void:
	_http_request.set_meta("file_type", file_type)
	_http_request.set_meta("new_version", new_version)
	
	var error: Error = _http_request.request(url)
	if error != OK:
		push_error("An error occurred in the HTTP request for %s." % file_type)
		_load_with_fallback(file_type)
		current_patch_index += 1
		call_deferred("_patch_next_file")

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var file_type: String = _http_request.get_meta("file_type")
	var new_version: String = _http_request.get_meta("new_version")
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json_string: String = body.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(json_string)
		
		if parsed != null:
			_save_to_cache(file_type, json_string)
			_set_local_version(file_type, new_version)
			cached_data[file_type] = parsed
			patch_progress.emit(file_type, "Downloaded and cached")
		else:
			var err_msg = "CRITICAL ERROR: Failed to parse downloaded JSON for %s. Raw body: %s" % [file_type, json_string.substr(0, 500)]
			printerr(err_msg)
			push_error(err_msg)
			_load_with_fallback(file_type)
	else:
		var err_msg = "CRITICAL ERROR: HTTP Request failed for %s. Response Code: %d, Result Code: %d" % [file_type, response_code, result]
		printerr(err_msg)
		push_error(err_msg)
		_load_with_fallback(file_type)
		
	current_patch_index += 1
	call_deferred("_patch_next_file")

func _get_local_version(file_type: String) -> String:
	var versions: Dictionary = _load_versions_file()
	if versions.has(file_type):
		return versions[file_type]
	return ""

func _set_local_version(file_type: String, version: String) -> void:
	var versions: Dictionary = _load_versions_file()
	versions[file_type] = version
	_save_versions_file(versions)

func _load_versions_file() -> Dictionary:
	var path: String = "user://data/versions.json"
	if not FileAccess.file_exists(path):
		return {}
	
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file:
		var content: String = file.get_as_text()
		file.close()
		var parsed: Variant = JSON.parse_string(content)
		if parsed and parsed is Dictionary:
			return parsed
	return {}

func _save_versions_file(versions: Dictionary) -> void:
	var path: String = "user://data/versions.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(versions, "\t"))
		file.close()

func _cache_exists(file_type: String) -> bool:
	return FileAccess.file_exists("user://data/%s.json" % file_type)

func _save_to_cache(file_type: String, json_string: String) -> void:
	var path: String = "user://data/%s.json" % file_type
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()

func _load_from_cache(file_type: String) -> void:
	var path: String = "user://data/%s.json" % file_type
	if FileAccess.file_exists(path):
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file:
			var content: String = file.get_as_text()
			file.close()
			var parsed: Variant = JSON.parse_string(content)
			if parsed != null:
				cached_data[file_type] = parsed
				return
	
	push_warning("Failed to load %s from cache, using empty dictionary." % file_type)
	cached_data[file_type] = {}

func _load_with_fallback(file_type: String) -> void:
	if _cache_exists(file_type):
		_load_from_cache(file_type)
		return
	if _load_from_bundled_static(file_type):
		return
	_load_from_cache(file_type)

func _load_from_bundled_static(file_type: String) -> bool:
	for base_dir in BUNDLED_STATIC_DIRS:
		var path: String = "%s/%s.json" % [base_dir, file_type]
		if not FileAccess.file_exists(path):
			continue

		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if not file:
			continue

		var json_string: String = file.get_as_text()
		file.close()

		var parsed: Variant = JSON.parse_string(json_string)
		if parsed == null:
			continue

		cached_data[file_type] = parsed
		_save_to_cache(file_type, json_string)
		_set_local_version(file_type, BUNDLED_STATIC_VERSION)
		patch_progress.emit(file_type, "Loaded bundled static data")
		return true

	return false

func get_data(file_type: String) -> Variant:
	if cached_data.has(file_type):
		return cached_data[file_type]
	return {}

func get_versions_snapshot() -> Dictionary:
	return _load_versions_file()
