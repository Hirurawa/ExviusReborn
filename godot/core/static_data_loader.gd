extends Node

signal patch_progress(file_name: String, status: String)
signal patch_complete

var files_to_patch: Array[String] = ["units", "items", "worlds", "dungeons", "towns", "missions", "skills_ability", "skills_magic", "skills_passive", "equipment", "limitbursts", "materia", "equipment-icons", "monsters", "summons", "summons_boards", "summons_exp_patterns", "summons_stat_patterns", "unit_exp_patterns", "rank_exp"]
var current_patch_index: int = 0
const BUNDLED_STATIC_VERSION: String = "bundled-v1"
const BUNDLED_STATIC_DIRS: Array[String] = ["res://assets/static_data", "res://assets"]

var cached_data: Dictionary = {}

func _ready() -> void:
	_ensure_user_data_dir()

func _ensure_user_data_dir() -> void:
	# Create user://data for local static cache files (json/csv).
	var dir: DirAccess = DirAccess.open("user://")
	if dir and not dir.dir_exists("data"):
		dir.make_dir("data")

func start_patching() -> void:
	current_patch_index = 0
	_load_next_file()

func _load_next_file() -> void:
	if current_patch_index >= files_to_patch.size():
		_dbg_mem("patch_complete")
		patch_complete.emit()
		return
		
	var file_type: String = files_to_patch[current_patch_index]
	patch_progress.emit(file_type, "Loading...")

	_dbg_mem("before " + file_type)
	# Load from cache or bundled static data
	_load_with_fallback(file_type)
	_dbg_mem("after  " + file_type)
	current_patch_index += 1
	call_deferred("_load_next_file")

func _dbg_mem(tag: String) -> void:
	if not OS.is_debug_build():
		return
	var mb: float = float(OS.get_static_memory_usage()) / 1048576.0
	print("[SDL] %-40s static=%.1fMB" % [tag, mb])

func _cache_exists(file_type: String) -> bool:
	return FileAccess.file_exists("user://data/%s.json" % file_type)

func _save_to_cache(file_type: String, json_string: String) -> void:
	_ensure_user_data_dir()
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
	# Note: no longer mirrors the JSON into user://data/<file>.json. The per-dataset
	# .bin cache written by StaticData supersedes that mirror, and the mirror was
	# ~130 MB of duplicated storage plus a synchronous write on the cold path.
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
		patch_progress.emit(file_type, "Loaded from bundled static data")
		return true

	return false

func get_data(file_type: String) -> Variant:
	if cached_data.has(file_type):
		return cached_data[file_type]
	return {}

# Streaming, non-caching parse of a single dataset. Returns the freshly-parsed
# Variant without populating `cached_data`, so the caller controls lifetime
# (StaticData uses this for memory-bounded cold-path sanitize-and-write).
func load_one(file_type: String) -> Variant:
	for base_dir in BUNDLED_STATIC_DIRS:
		var path: String = "%s/%s.json" % [base_dir, file_type]
		if not FileAccess.file_exists(path):
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if not file:
			continue
		var content: String = file.get_as_text()
		file.close()
		var parsed: Variant = JSON.parse_string(content)
		if parsed != null:
			return parsed
	return null

func get_versions_snapshot() -> Dictionary:
	# Return source-aware version info so downstream caches invalidate when JSON changes.
	var versions: Dictionary = {}
	for file_type in files_to_patch:
		versions[file_type] = _build_source_version_token(file_type)
	return versions

func _build_source_version_token(file_type: String) -> String:
	# Use only the bundled file's size for the signature. The previously-used
	# resolved path + mtime were unstable: the path flips between res:// and
	# user://data/ once _save_to_cache mirrors a JSON, and the mtime changes
	# every time that mirror is rewritten. That made the sanitized-cache
	# signature mismatch on every launch and forced a full ~130 MB JSON parse
	# + sanitize cycle (peaking near 1 GB heap on Android).
	var bundled_path: String = ""
	for base_dir in BUNDLED_STATIC_DIRS:
		var candidate: String = "%s/%s.json" % [base_dir, file_type]
		if FileAccess.file_exists(candidate):
			bundled_path = candidate
			break
	if bundled_path == "":
		return "missing"

	var file_size: int = -1
	var file: FileAccess = FileAccess.open(bundled_path, FileAccess.READ)
	if file:
		file_size = file.get_length()
		file.close()

	return "%s|%s" % [BUNDLED_STATIC_VERSION, str(file_size)]

func _resolve_source_path(file_type: String) -> String:
	var cache_path: String = "user://data/%s.json" % file_type
	if FileAccess.file_exists(cache_path):
		return cache_path

	for base_dir in BUNDLED_STATIC_DIRS:
		var bundled_path: String = "%s/%s.json" % [base_dir, file_type]
		if FileAccess.file_exists(bundled_path):
			return bundled_path

	return ""

func _build_static_data_candidates(file_name: String) -> PackedStringArray:
	var candidates: PackedStringArray = []
	for base_dir in BUNDLED_STATIC_DIRS:
		candidates.append("%s/%s" % [base_dir, file_name])
	return candidates

func _resolve_static_data_file_path(file_name: String) -> String:
	var candidates: PackedStringArray = _build_static_data_candidates(file_name)
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""

func _build_csv_cache_path(file_name: String) -> String:
	return "user://data/%s" % file_name

func resolve_or_cache_static_csv(file_name: String) -> String:
	_ensure_user_data_dir()

	var cached_path: String = _build_csv_cache_path(file_name)
	if FileAccess.file_exists(cached_path):
		return cached_path

	var bundled_path: String = _resolve_static_data_file_path(file_name)
	if bundled_path == "":
		return ""

	var source_file: FileAccess = FileAccess.open(bundled_path, FileAccess.READ)
	if not source_file:
		return bundled_path

	var content: String = source_file.get_as_text()
	source_file.close()

	var cache_file: FileAccess = FileAccess.open(cached_path, FileAccess.WRITE)
	if not cache_file:
		push_warning("Unable to cache %s to %s, using bundled file" % [file_name, cached_path])
		return bundled_path

	cache_file.store_string(content)
	cache_file.close()

	if FileAccess.file_exists(cached_path):
		return cached_path

	return bundled_path

func load_rank_exp_data() -> Dictionary:
	# Load and parse rank_exp.json.
	# JSON structure: {"<rank>": {"Exp": int, "Energy": int, ...}, ...}
	# Exp at rank N is treated as XP needed to advance FROM rank N TO rank N+1.
	# Result: rank_data[rank] = {"xp_needed": int, "energy": int}

	var rank_data: Dictionary = {}
	# Use the same cache-first path resolution as patched static JSON files.
	var json_path: String = _resolve_source_path("rank_exp")

	if json_path == "":
		var attempted_paths: PackedStringArray = _build_static_data_candidates("rank_exp.json")
		attempted_paths.append(_build_csv_cache_path("rank_exp.json"))
		push_error("rank_exp.json not found. Attempted paths: %s" % ", ".join(attempted_paths))
		return rank_data

	var file: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		push_error("Failed to open rank_exp.json")
		return rank_data

	var content: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(content)
	if not (parsed is Dictionary):
		push_error("rank_exp.json parse failed or root is not an object")
		return rank_data

	var rows: Dictionary = parsed
	var sorted_ranks: Array[int] = []
	for rank_key in rows.keys():
		var rank_text: String = str(rank_key).strip_edges()
		if rank_text == "" or not rank_text.is_valid_int():
			push_warning("Skipping rank_exp.json row with invalid rank key: %s" % str(rank_key))
			continue
		sorted_ranks.append(int(rank_text))

	sorted_ranks.sort()

	for rank in sorted_ranks:
		var row_value: Variant = rows.get(str(rank), null)
		if not (row_value is Dictionary):
			push_warning("Skipping rank %d in rank_exp.json: row is not an object" % rank)
			continue

		var row: Dictionary = row_value
		if not row.has("Exp") or not row.has("Energy"):
			push_warning("Skipping rank %d in rank_exp.json: missing Exp or Energy" % rank)
			continue

		var exp_raw: Variant = row.get("Exp", 0)
		var energy_raw: Variant = row.get("Energy", 0)
		if exp_raw == null:
			# Max rank rows commonly have null Exp (no further progression).
			continue
		if energy_raw == null:
			energy_raw = 0
		var xp_needed: int = int(exp_raw)
		var energy: int = int(energy_raw)
		if xp_needed <= 0:
			push_warning("Skipping rank %d in rank_exp.json: Exp must be > 0" % rank)
			continue

		rank_data[rank] = {
			"xp_needed": xp_needed,
			"energy": energy
		}

	return rank_data
