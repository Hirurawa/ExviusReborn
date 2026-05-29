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
	_dbg_mem("_on_patch_complete enter")
	var cache_signature: String = build_signature()

	if _try_load_sanitized_cache(cache_signature):
		_dbg_mem("loaded sanitized cache (fast)")
		_notify_skill_resolver()
		return

	# Memory-friendly sanitize: walk one file at a time and immediately drop the
	# raw parsed copy held by StaticDataLoader, so we never hold two trees at once.
	# On Android the raw parse already peaks near the per-process heap cap, so we
	# cannot afford the previous "double everything in flight" pattern.
	game_data_units = _sanitize_and_drop("units")
	_dbg_mem("sanitized units")
	game_data_items = _sanitize_and_drop("items")
	_dbg_mem("sanitized items")
	game_data_equipment = _sanitize_and_drop("equipment")
	_dbg_mem("sanitized equipment")
	game_data_worlds = _sanitize_and_drop("worlds")
	game_data_dungeons = _sanitize_and_drop("dungeons")
	game_data_towns = _sanitize_and_drop("towns")
	game_data_missions = _sanitize_and_drop("missions")
	_dbg_mem("sanitized worlds..missions")
	game_data_skills_magic = _sanitize_and_drop("skills_magic")
	game_data_skills_ability = _sanitize_and_drop("skills_ability")
	game_data_skills_passive = _sanitize_and_drop("skills_passive")
	_dbg_mem("sanitized skills_*")
	game_data_limitbursts = _sanitize_and_drop("limitbursts")
	_normalize_limitburst_effects_raw()
	game_data_materia = _sanitize_and_drop("materia")
	game_data_equipment_icons = _sanitize_and_drop("equipment-icons")
	game_data_monsters = _sanitize_and_drop("monsters")
	_dbg_mem("sanitized lb/materia/icons/monsters")
	game_data_summons = _sanitize_and_drop("summons")
	game_data_summons_boards = _sanitize_and_drop("summons_boards")
	game_data_summons_exp_patterns = _sanitize_and_drop("summons_exp_patterns")
	game_data_summons_stat_patterns = _sanitize_and_drop("summons_stat_patterns")
	game_data_unit_exp_patterns = _sanitize_and_drop("unit_exp_patterns")
	_dbg_mem("sanitized summons/exp")

	_save_sanitized_cache(cache_signature)
	_dbg_mem("after _save_sanitized_cache")
	_notify_skill_resolver()
	_dbg_mem("_on_patch_complete exit")


func _sanitize_and_drop(file_type: String) -> Variant:
	var sanitized: Variant = _sanitize_floats_to_ints(StaticDataLoader.get_data(file_type))
	# Release the raw parsed copy. After this, the only live reference to this
	# dataset is the local `sanitized` we return to the caller.
	StaticDataLoader.cached_data.erase(file_type)
	return sanitized

func _dbg_mem(tag: String) -> void:
	var mb: float = float(OS.get_static_memory_usage()) / 1048576.0
	print("[STD] %-40s static=%.1fMB" % [tag, mb])


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

	# Fallback: if we shipped a pre-baked cache in res:// (e.g. inside the
	# Android assets.pck), seed user:// from it. This avoids ever JSON-parsing
	# the ~130 MB of bundled static data on device, which otherwise peaks the
	# heap near ~1 GB and OOMs on Android.
	if not FileAccess.file_exists(bin_path):
		_seed_user_cache_from_baked()

	if not FileAccess.file_exists(sig_path) or not FileAccess.file_exists(bin_path):
		print("[STD] fast-path miss: sig_exists=%s bin_exists=%s" % [FileAccess.file_exists(sig_path), FileAccess.file_exists(bin_path)])
		return false

	var sig_file: FileAccess = FileAccess.open(sig_path, FileAccess.READ)
	if not sig_file:
		print("[STD] fast-path miss: could not open sig file")
		return false
	var stored_sig: String = sig_file.get_as_text().strip_edges()
	sig_file.close()

	if stored_sig != signature:
		print("[STD] fast-path miss: signature mismatch")
		print("[STD]   stored : %s" % stored_sig.substr(0, 200))
		print("[STD]   wanted : %s" % signature.substr(0, 200))
		return false

	_dbg_mem("fast-path: before get_file_as_bytes")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(bin_path)
	_dbg_mem("fast-path: after get_file_as_bytes size=%d" % bytes.size())
	if bytes.is_empty():
		print("[STD] fast-path miss: bin file is empty")
		return false

	var decoded: Variant = bytes_to_var(bytes)
	_dbg_mem("fast-path: after bytes_to_var typeof=%d" % typeof(decoded))
	if not (decoded is Dictionary):
		print("[STD] fast-path miss: bytes_to_var did not return Dictionary (got type %d)" % typeof(decoded))
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


func _seed_user_cache_from_baked() -> void:
	# Copy a pre-baked sanitized cache shipped in the PCK into user://data/.
	# Lets first launch on Android skip JSON parsing of ~130 MB of bundled
	# static data, which otherwise peaks heap near ~1 GB and OOMs.
	# Bake instructions: run the game once on desktop, then copy
	#   <user_data_dir>/data/sanitized_data_cache.bin
	# into godot/baked_static_cache/ before exporting the Android assets PCK.
	# (The .sig file is NOT copied — we re-derive it from the device's own
	# bundled file versions so signature comparison passes.)
	var baked_bin: String = "res://baked_static_cache/sanitized_data_cache.bin"
	if not FileAccess.file_exists(baked_bin):
		return

	var dir: DirAccess = DirAccess.open("user://")
	if dir and not dir.dir_exists("data"):
		dir.make_dir("data")

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(baked_bin)
	if bytes.is_empty():
		return
	var out_bin: FileAccess = FileAccess.open("user://data/sanitized_data_cache.bin", FileAccess.WRITE)
	if not out_bin:
		return
	out_bin.store_buffer(bytes)
	out_bin.close()

	# Write a sig matching the device's own resolved bundled file versions so
	# the subsequent signature check accepts this cache as fresh.
	var device_sig: String = build_signature()
	var out_sig: FileAccess = FileAccess.open("user://data/sanitized_cache_sig.txt", FileAccess.WRITE)
	if out_sig:
		out_sig.store_string(device_sig)
		out_sig.close()

	print("[STD] Seeded user:// cache from baked res:// snapshot (%d bytes)" % bytes.size())


func _notify_skill_resolver() -> void:
	# SkillResolver loads opcode schemas after data is in place. Resolved by
	# autoload name; safe at runtime because prime_cache() is invoked deferred
	# from DataManager._ready, after all autoloads are constructed.
	var resolver: Node = get_node_or_null("/root/SkillResolver")
	if resolver and resolver.has_method("load_schemas"):
		resolver.load_schemas()
