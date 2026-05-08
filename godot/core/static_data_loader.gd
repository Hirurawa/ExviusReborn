extends Node

signal patch_progress(file_name: String, status: String)
signal patch_complete

var files_to_patch: Array[String] = ["units", "items", "worlds", "dungeons", "missions", "skills_ability", "skills_magic", "skills_passive", "equipment", "limitbursts", "materia", "equipment-icons", "monsters", "summons", "summons_boards", "summons_exp_patterns", "summons_stat_patterns"]
var current_patch_index: int = 0
const BUNDLED_STATIC_VERSION: String = "bundled-v1"
const BUNDLED_STATIC_DIRS: Array[String] = ["res://assets/static_data", "res://assets"]

var cached_data: Dictionary = {}

func _ready() -> void:
	# Create data dir if it doesn't exist
	var dir: DirAccess = DirAccess.open("user://")
	if not dir.dir_exists("data"):
		dir.make_dir("data")

func start_patching() -> void:
	current_patch_index = 0
	_load_next_file()

func _load_next_file() -> void:
	if current_patch_index >= files_to_patch.size():
		patch_complete.emit()
		return
		
	var file_type: String = files_to_patch[current_patch_index]
	patch_progress.emit(file_type, "Loading...")

	# Load from cache or bundled static data
	_load_with_fallback(file_type)
	current_patch_index += 1
	call_deferred("_load_next_file")

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
		patch_progress.emit(file_type, "Loaded from bundled static data")
		return true

	return false

func get_data(file_type: String) -> Variant:
	if cached_data.has(file_type):
		return cached_data[file_type]
	return {}

func get_versions_snapshot() -> Dictionary:
	# Return minimal version info for diagnostics
	var versions: Dictionary = {}
	for file_type in files_to_patch:
		versions[file_type] = BUNDLED_STATIC_VERSION if cached_data.has(file_type) else "not-loaded"
	return versions
