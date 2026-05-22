extends Node
## StaticData — owns the in-memory `game_data_*` dictionaries and the patch /
## sanitize / cache lifecycle previously embedded in DataManager.
##
## Public state remains accessible by name (e.g. `StaticData.game_data_units`)
## so DataManager can forward via property getters without breaking any reader.
##
## SkillResolver is notified after a load completes so it can (re)read its
## opcode schemas. We intentionally do not depend on any other domain service.

signal data_primed

var game_data_units: Dictionary = {}
var game_data_items: Dictionary = {}
var game_data_equipment: Dictionary = {}
var game_data_worlds: Dictionary = {}
var game_data_dungeons: Dictionary = {}
var game_data_towns: Dictionary = {}
var game_data_missions: Dictionary = {}
var game_data_skills_magic: Dictionary = {}
var game_data_skills_ability: Dictionary = {}
var game_data_skills_passive: Dictionary = {}
var game_data_limitbursts: Dictionary = {}
var game_data_materia: Dictionary = {}
var game_data_equipment_icons: Dictionary = {}
var game_data_monsters: Array = []
var game_data_summons: Dictionary = {}
var game_data_summons_boards: Dictionary = {}
var game_data_summons_exp_patterns: Dictionary = {}
var game_data_summons_stat_patterns: Dictionary = {}
var game_data_unit_exp_patterns: Dictionary = {}

var is_ready: bool = false
var synced_with_server: bool = false

var _loading: bool = false
var _sync_queued: bool = false


# === Public lifecycle ===

func ensure_ready() -> void:
	if _loading:
		await data_primed

	if not is_ready:
		await prime_cache()

	if needs_refresh():
		await refresh_cache()


func prime_cache() -> void:
	if is_ready or _loading:
		return

	_loading = true

	# Fast path: if sanitized cache matches on-disk versions, skip patcher entirely.
	var early_sig: String = build_signature()
	if early_sig != "" and _try_load_sanitized_cache(early_sig):
		_notify_skill_resolver()
		is_ready = true
		synced_with_server = false
		_loading = false
		data_primed.emit()
		return

	var did_sync: bool = await _run_patch_cycle()
	synced_with_server = did_sync

	is_ready = true
	_loading = false
	data_primed.emit()


func refresh_cache() -> void:
	if _loading:
		await data_primed
		return

	_loading = true
	var did_sync: bool = await _run_patch_cycle()
	synced_with_server = did_sync
	is_ready = true
	_loading = false
	data_primed.emit()


func run_background_sync() -> void:
	_sync_queued = false
	await refresh_cache()


func needs_refresh() -> bool:
	if not StaticDataLoader or not StaticDataLoader.has_method("get_versions_snapshot"):
		return false

	var versions: Dictionary = StaticDataLoader.get_versions_snapshot()
	for file_type in StaticDataLoader.files_to_patch:
		if str(versions.get(file_type, "")).strip_edges() == "":
			return true
		if not FileAccess.file_exists("user://data/%s.json" % file_type):
			return true

	return false


# === Patch cycle ===

func _run_patch_cycle() -> bool:
	if not StaticDataLoader.patch_complete.is_connected(_on_patch_complete):
		StaticDataLoader.patch_progress.connect(func(_file_name, _status):
			pass
		)
		StaticDataLoader.patch_complete.connect(_on_patch_complete)

	StaticDataLoader.start_patching()
	await StaticDataLoader.patch_complete
	return false


func _on_patch_complete() -> void:
	var cache_signature: String = build_signature()

	if _try_load_sanitized_cache(cache_signature):
		_notify_skill_resolver()
		return

	game_data_units = _sanitize_floats_to_ints(StaticDataLoader.get_data("units"))
	game_data_items = _sanitize_floats_to_ints(StaticDataLoader.get_data("items"))
	game_data_equipment = _sanitize_floats_to_ints(StaticDataLoader.get_data("equipment"))
	game_data_worlds = _sanitize_floats_to_ints(StaticDataLoader.get_data("worlds"))
	game_data_dungeons = _sanitize_floats_to_ints(StaticDataLoader.get_data("dungeons"))
	game_data_towns = _sanitize_floats_to_ints(StaticDataLoader.get_data("towns"))
	game_data_missions = _sanitize_floats_to_ints(StaticDataLoader.get_data("missions"))
	game_data_skills_magic = _sanitize_floats_to_ints(StaticDataLoader.get_data("skills_magic"))
	game_data_skills_ability = _sanitize_floats_to_ints(StaticDataLoader.get_data("skills_ability"))
	game_data_skills_passive = _sanitize_floats_to_ints(StaticDataLoader.get_data("skills_passive"))
	game_data_limitbursts = _sanitize_floats_to_ints(StaticDataLoader.get_data("limitbursts"))
	_normalize_limitburst_effects_raw()
	game_data_materia = _sanitize_floats_to_ints(StaticDataLoader.get_data("materia"))
	game_data_equipment_icons = _sanitize_floats_to_ints(StaticDataLoader.get_data("equipment-icons"))
	game_data_monsters = _sanitize_floats_to_ints(StaticDataLoader.get_data("monsters"))
	game_data_summons = _sanitize_floats_to_ints(StaticDataLoader.get_data("summons"))
	game_data_summons_boards = _sanitize_floats_to_ints(StaticDataLoader.get_data("summons_boards"))
	game_data_summons_exp_patterns = _sanitize_floats_to_ints(StaticDataLoader.get_data("summons_exp_patterns"))
	game_data_summons_stat_patterns = _sanitize_floats_to_ints(StaticDataLoader.get_data("summons_stat_patterns"))
	game_data_unit_exp_patterns = _sanitize_floats_to_ints(StaticDataLoader.get_data("unit_exp_patterns"))

	_save_sanitized_cache(cache_signature)
	_notify_skill_resolver()


# === Sanitization & cache ===

func _sanitize_floats_to_ints(data: Variant) -> Variant:
	return sanitize_floats_to_ints(data)


func sanitize_floats_to_ints(data: Variant) -> Variant:
	if typeof(data) == TYPE_DICTIONARY:
		var new_dict: Dictionary = {}
		for key in data:
			new_dict[key] = sanitize_floats_to_ints(data[key])
		return new_dict
	elif typeof(data) == TYPE_ARRAY:
		var new_array: Array = []
		for item in data:
			new_array.append(sanitize_floats_to_ints(item))
		return new_array
	elif typeof(data) == TYPE_FLOAT:
		if fmod(data, 1.0) == 0.0:
			return int(data)
	return data


func build_signature() -> String:
	if not StaticDataLoader or not StaticDataLoader.has_method("get_versions_snapshot"):
		return ""

	var versions: Dictionary = StaticDataLoader.get_versions_snapshot()
	var parts: Array[String] = []

	for file_type in StaticDataLoader.files_to_patch:
		parts.append("%s=%s" % [file_type, str(versions.get(file_type, ""))])

	return "|".join(parts)


func _try_load_sanitized_cache(signature: String) -> bool:
	if signature == "":
		return false

	var sig_path: String = "user://data/sanitized_cache_sig.txt"
	var bin_path: String = "user://data/sanitized_data_cache.bin"
	if not FileAccess.file_exists(sig_path) or not FileAccess.file_exists(bin_path):
		return false

	var sig_file: FileAccess = FileAccess.open(sig_path, FileAccess.READ)
	if not sig_file:
		return false
	var stored_sig: String = sig_file.get_as_text().strip_edges()
	sig_file.close()

	if stored_sig != signature:
		return false

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(bin_path)
	if bytes.is_empty():
		return false

	var decoded: Variant = bytes_to_var(bytes)
	if not (decoded is Dictionary):
		return false

	var datasets: Dictionary = decoded
	game_data_units = datasets.get("units", {})
	game_data_items = datasets.get("items", {})
	game_data_equipment = datasets.get("equipment", {})
	game_data_worlds = datasets.get("worlds", {})
	game_data_dungeons = datasets.get("dungeons", {})
	game_data_towns = datasets.get("towns", {})
	game_data_missions = datasets.get("missions", {})
	game_data_skills_magic = datasets.get("skills_magic", {})
	game_data_skills_ability = datasets.get("skills_ability", {})
	game_data_skills_passive = datasets.get("skills_passive", {})
	game_data_limitbursts = datasets.get("limitbursts", {})
	_normalize_limitburst_effects_raw()
	game_data_materia = datasets.get("materia", {})
	game_data_equipment_icons = datasets.get("equipment-icons", {})
	game_data_monsters = datasets.get("monsters", [])
	game_data_summons = datasets.get("summons", {})
	game_data_summons_boards = datasets.get("summons_boards", {})
	game_data_summons_exp_patterns = datasets.get("summons_exp_patterns", {})
	game_data_summons_stat_patterns = datasets.get("summons_stat_patterns", {})
	game_data_unit_exp_patterns = datasets.get("unit_exp_patterns", {})
	return true


func _normalize_limitburst_effects_raw() -> void:
	for limitburst_id in game_data_limitbursts.keys():
		var limitburst_data: Variant = game_data_limitbursts.get(limitburst_id, {})
		if not (limitburst_data is Dictionary):
			continue

		var limitburst_dict: Dictionary = limitburst_data
		var levels_value: Variant = limitburst_dict.get("levels", [])
		if not (levels_value is Array):
			continue

		var levels: Array = levels_value
		if levels.is_empty():
			continue

		var first_level_value: Variant = levels[0]
		if not (first_level_value is Array):
			continue

		var first_level: Array = first_level_value
		if first_level.size() < 2:
			continue

		var effects_raw_value: Variant = first_level[1]
		if not (effects_raw_value is Array):
			continue

		limitburst_dict["effects_raw"] = effects_raw_value
		game_data_limitbursts[limitburst_id] = limitburst_dict


func _save_sanitized_cache(signature: String) -> void:
	if signature == "":
		return

	var datasets: Dictionary = {
		"units": game_data_units,
		"items": game_data_items,
		"equipment": game_data_equipment,
		"worlds": game_data_worlds,
		"dungeons": game_data_dungeons,
		"towns": game_data_towns,
		"missions": game_data_missions,
		"skills_magic": game_data_skills_magic,
		"skills_ability": game_data_skills_ability,
		"skills_passive": game_data_skills_passive,
		"limitbursts": game_data_limitbursts,
		"materia": game_data_materia,
		"equipment-icons": game_data_equipment_icons,
		"monsters": game_data_monsters,
		"summons": game_data_summons,
		"summons_boards": game_data_summons_boards,
		"summons_exp_patterns": game_data_summons_exp_patterns,
		"summons_stat_patterns": game_data_summons_stat_patterns,
		"unit_exp_patterns": game_data_unit_exp_patterns
	}

	var bin_path: String = "user://data/sanitized_data_cache.bin"
	var bin_file: FileAccess = FileAccess.open(bin_path, FileAccess.WRITE)
	if not bin_file:
		return
	bin_file.store_buffer(var_to_bytes(datasets))
	bin_file.close()

	var sig_path: String = "user://data/sanitized_cache_sig.txt"
	var sig_file: FileAccess = FileAccess.open(sig_path, FileAccess.WRITE)
	if sig_file:
		sig_file.store_string(signature)
		sig_file.close()


func _notify_skill_resolver() -> void:
	# SkillResolver loads opcode schemas after data is in place. Resolved by
	# autoload name; safe at runtime because prime_cache() is invoked deferred
	# from DataManager._ready, after all autoloads are constructed.
	var resolver: Node = get_node_or_null("/root/SkillResolver")
	if resolver and resolver.has_method("load_schemas"):
		resolver.load_schemas()
