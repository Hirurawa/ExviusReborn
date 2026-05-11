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
	# Return source-aware version info so downstream caches invalidate when JSON changes.
	var versions: Dictionary = {}
	for file_type in files_to_patch:
		versions[file_type] = _build_source_version_token(file_type)
	return versions

func _build_source_version_token(file_type: String) -> String:
	var source_path: String = _resolve_source_path(file_type)
	if source_path == "":
		return "missing"

	var modified_unix: int = FileAccess.get_modified_time(source_path)
	var file_size: int = -1
	var file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if file:
		file_size = file.get_length()
		file.close()

	return "%s|%s|%s|%s" % [BUNDLED_STATIC_VERSION, source_path, str(modified_unix), str(file_size)]

func _resolve_source_path(file_type: String) -> String:
	var cache_path: String = "user://data/%s.json" % file_type
	if FileAccess.file_exists(cache_path):
		return cache_path

	for base_dir in BUNDLED_STATIC_DIRS:
		var bundled_path: String = "%s/%s.json" % [base_dir, file_type]
		if FileAccess.file_exists(bundled_path):
			return bundled_path

	return ""

func load_rank_exp_data() -> Dictionary:
	# Load and parse rank-exp.csv
	# CSV structure: Rank, Exp (XP needed to reach that rank), Energy, Friend slot
	# The Exp value at rank N = XP needed to advance from rank N-1 to rank N
	# Result: rank_data[rank] = {"xp_needed": int, "energy": int}
	#   where xp_needed = XP to advance FROM rank TO rank+1
	
	var rank_data: Dictionary = {}
	var csv_path: String = "res://assets/static_data/rank-exp.csv"
	
	if not FileAccess.file_exists(csv_path):
		push_error("rank-exp.csv not found at %s" % csv_path)
		return rank_data
	
	var file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if not file:
		push_error("Failed to open rank-exp.csv")
		return rank_data
	
	var content: String = file.get_as_text()
	file.close()
	
	var lines: PackedStringArray = content.split("\n")
	var csv_rows: Array = []
	
	# Parse CSV lines into an array (skip header)
	for i in range(1, lines.size()):
		var line: String = lines[i].strip_edges()
		if line == "":
			continue
		
		var columns: PackedStringArray = line.split(",")
		if columns.size() < 3:
			continue
		
		var rank: int = int(columns[0].strip_edges())
		var exp_str: String = columns[1].strip_edges()
		var energy: int = int(columns[2].strip_edges())
		
		var exp_value: int = 0
		if exp_str != "-":
			exp_value = int(exp_str)
		
		csv_rows.append({"rank": rank, "exp": exp_value, "energy": energy})
	
	# Build rank_data: 
	# - rank_data[N] contains XP needed to go from rank N to rank N+1
	# - CSV row N has the XP needed to reach rank N (i.e., from rank N-1 to rank N)
	for i in range(csv_rows.size()):
		var row = csv_rows[i]
		var current_rank = row["rank"]
		var current_energy = row["energy"]
		var xp_to_reach_this_rank = row["exp"]
		
		# The XP value in this row applies to advancing from previous rank to current rank
		if current_rank > 1 and xp_to_reach_this_rank > 0:
			var prev_rank = current_rank - 1
			var prev_energy = csv_rows[i-1]["energy"] if i > 0 else 41
			rank_data[prev_rank] = {
				"xp_needed": xp_to_reach_this_rank,
				"energy": prev_energy
			}
	
	return rank_data
