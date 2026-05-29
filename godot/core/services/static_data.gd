extends Node
## StaticData — owns access to the `game_data_*` datasets via lazy per-dataset
## binary caches. Public state remains accessible by name
## (`StaticData.game_data_units`, etc.) so the ~170 reader sites are unchanged,
## but the underlying dictionaries are no longer all resident at once.
##
## Memory model:
##  * Each of the 19 datasets is stored on disk as its own sanitized .bin file
##    under user://data/sanitized/<key>.bin.
##  * A single manifest (user://data/sanitized/manifest.txt) holds the build
##    signature; if it matches, all bins are considered fresh.
##  * `_get(game_data_X)` decodes the matching bin on first access and caches
##    the result in `_loaded`. Subsequent reads are O(1).
##  * `evict_dataset(key)` / `evict_all()` drop loaded copies to reclaim RAM
##    when scenes know a dataset won't be needed again soon.
##
## Cold path (first launch / signature mismatch) still walks the patcher,
## sanitizes everything, writes the per-dataset bins, and keeps everything
## resident for the rest of that session (callers need it during initial
## hydration anyway). Subsequent launches use the lazy path and only pay for
## what gets accessed.

signal data_primed

const SANITIZED_DIR: String = "user://data/sanitized"
const MANIFEST_PATH: String = "user://data/sanitized/manifest.txt"
const BAKED_SANITIZED_DIR: String = "res://baked_static_cache/sanitized"

# Legacy paths cleaned up on first launch after upgrading to per-dataset cache.
const LEGACY_MONOLITHIC_BIN: String = "user://data/sanitized_data_cache.bin"
const LEGACY_MONOLITHIC_SIG: String = "user://data/sanitized_cache_sig.txt"

# Property name -> on-disk dataset key. Property names match the historical
# `game_data_*` fields so existing call sites keep working.
const _PROP_TO_KEY: Dictionary = {
	"game_data_units": "units",
	"game_data_items": "items",
	"game_data_equipment": "equipment",
	"game_data_worlds": "worlds",
	"game_data_dungeons": "dungeons",
	"game_data_towns": "towns",
	"game_data_missions": "missions",
	"game_data_skills_magic": "skills_magic",
	"game_data_skills_ability": "skills_ability",
	"game_data_skills_passive": "skills_passive",
	"game_data_limitbursts": "limitbursts",
	"game_data_materia": "materia",
	"game_data_equipment_icons": "equipment-icons",
	"game_data_monsters": "monsters",
	"game_data_summons": "summons",
	"game_data_summons_boards": "summons_boards",
	"game_data_summons_exp_patterns": "summons_exp_patterns",
	"game_data_summons_stat_patterns": "summons_stat_patterns",
	"game_data_unit_exp_patterns": "unit_exp_patterns",
}

# Dataset key -> default empty value (everything is Dictionary except monsters).
const _DEFAULTS: Dictionary = {
	"units": {}, "items": {}, "equipment": {}, "worlds": {}, "dungeons": {},
	"towns": {}, "missions": {}, "skills_magic": {}, "skills_ability": {},
	"skills_passive": {}, "limitbursts": {}, "materia": {}, "equipment-icons": {},
	"monsters": [], "summons": {}, "summons_boards": {},
	"summons_exp_patterns": {}, "summons_stat_patterns": {}, "unit_exp_patterns": {},
}

var is_ready: bool = false
var synced_with_server: bool = false

# Per-key cache of decoded datasets. Populated lazily by `_get` or eagerly by
# the cold path during `_on_patch_complete`.
var _loaded: Dictionary = {}

var _loading: bool = false
var _sync_queued: bool = false
var _signature_valid: bool = false # set true once per-dataset bins+manifest verified


# === Property bridge ===

func _get(property: StringName) -> Variant:
	var name: String = String(property)
	if _PROP_TO_KEY.has(name):
		return _ensure_dataset(_PROP_TO_KEY[name])
	return null


func _set(property: StringName, value: Variant) -> bool:
	var name: String = String(property)
	if _PROP_TO_KEY.has(name):
		_loaded[_PROP_TO_KEY[name]] = value
		return true
	return false


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
	_ensure_sanitized_dir()
	_cleanup_legacy_monolithic_cache()

	var sig: String = build_signature()

	# If the user hasn't got per-dataset bins yet but the PCK ships a baked
	# snapshot, copy those over and re-derive the manifest from the device's
	# own bundled JSON sizes so the signature check accepts them.
	if not _have_manifest():
		_seed_user_cache_from_baked()

	if sig != "" and _per_dataset_caches_valid(sig):
		# Hot path: nothing loaded into RAM yet. Lazy `_get` will pull
		# individual datasets only when first accessed.
		print("[STD] lazy fast-path: per-dataset cache valid (no load yet)")
		_signature_valid = true
		_notify_skill_resolver()
		is_ready = true
		synced_with_server = false
		_loading = false
		data_primed.emit()
		return

	# Cold path: parse JSONs, sanitize, write per-dataset bins. Keep everything
	# resident for this session since callers will hit most datasets shortly.
	print("[STD] cold path: signature mismatch or missing, running patcher")
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


# === Eviction API ===

func evict_dataset(key: String) -> void:
	_loaded.erase(key)


func evict_all() -> void:
	_loaded.clear()


# Caller-friendly batch evictions. Scenes that know they're done with a set of
# datasets can call these to drop them; they will reload lazily if anyone
# touches them again.
func evict_outgame_only_datasets() -> void:
	for k in ["summons_boards", "summons_exp_patterns", "summons_stat_patterns",
			"equipment-icons", "unit_exp_patterns", "worlds", "towns"]:
		_loaded.erase(k)


# === Lazy loader ===

func _ensure_dataset(key: String) -> Variant:
	if _loaded.has(key):
		return _loaded[key]

	# Not loaded yet. If we don't have a verified per-dataset cache, return a
	# transient empty default WITHOUT caching it. The cold path is in flight
	# and will populate `_loaded` shortly; future reads will then see real data.
	if not _signature_valid:
		return _default_for(key)

	var decoded: Variant = _load_dataset_from_disk(key)
	if decoded == null:
		push_warning("StaticData: failed to lazy-load dataset '%s'; returning empty default" % key)
		return _default_for(key)

	_loaded[key] = decoded
	if key == "limitbursts":
		_normalize_limitburst_effects_raw()
	return _loaded[key]


func _default_for(key: String) -> Variant:
	var d: Variant = _DEFAULTS.get(key, {})
	if d is Dictionary:
		return (d as Dictionary).duplicate()
	if d is Array:
		return (d as Array).duplicate()
	return d


func _load_dataset_from_disk(key: String) -> Variant:
	var path: String = "%s/%s.bin" % [SANITIZED_DIR, key]
	if not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var decoded: Variant = bytes_to_var(bytes)
	if decoded == null:
		return null
	return decoded


# === Patch cycle (cold path) ===

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

	# If a valid per-dataset cache already exists on disk (e.g. baked or from a
	# previous run), skip the sanitize + rewrite step entirely.
	if cache_signature != "" and _per_dataset_caches_valid(cache_signature):
		_dbg_mem("per-dataset cache already valid, no rewrite")
		_signature_valid = true
		_notify_skill_resolver()
		return

	_ensure_sanitized_dir()

	# Memory-friendly sanitize: walk one file at a time, immediately drop the
	# raw parsed copy held by StaticDataLoader, and write per-dataset bin so
	# subsequent launches can lazy-load.
	for prop_name in _PROP_TO_KEY.keys():
		var key: String = _PROP_TO_KEY[prop_name]
		var sanitized: Variant = _sanitize_and_drop(key)
		_loaded[key] = sanitized
		_write_dataset_bin(key, sanitized)
		_dbg_mem("sanitized+wrote %s" % key)

	if _loaded.has("limitbursts"):
		_normalize_limitburst_effects_raw()

	_write_manifest(cache_signature)
	_signature_valid = true
	_notify_skill_resolver()
	_dbg_mem("_on_patch_complete exit")


func _sanitize_and_drop(file_type: String) -> Variant:
	var sanitized: Variant = _sanitize_floats_to_ints(StaticDataLoader.get_data(file_type))
	StaticDataLoader.cached_data.erase(file_type)
	return sanitized


func _dbg_mem(tag: String) -> void:
	var mb: float = float(OS.get_static_memory_usage()) / 1048576.0
	print("[STD] %-40s static=%.1fMB" % [tag, mb])


# === Sanitization ===

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


# === Signature & per-dataset cache I/O ===

func build_signature() -> String:
	if not StaticDataLoader or not StaticDataLoader.has_method("get_versions_snapshot"):
		return ""

	var versions: Dictionary = StaticDataLoader.get_versions_snapshot()
	var parts: Array[String] = []

	for file_type in StaticDataLoader.files_to_patch:
		parts.append("%s=%s" % [file_type, str(versions.get(file_type, ""))])

	return "|".join(parts)


func _have_manifest() -> bool:
	return FileAccess.file_exists(MANIFEST_PATH)


func _per_dataset_caches_valid(signature: String) -> bool:
	if signature == "":
		return false
	if not FileAccess.file_exists(MANIFEST_PATH):
		return false

	var f: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if not f:
		return false
	var stored: String = f.get_as_text().strip_edges()
	f.close()

	if stored != signature:
		print("[STD] manifest mismatch")
		print("[STD]   stored : %s" % stored.substr(0, 200))
		print("[STD]   wanted : %s" % signature.substr(0, 200))
		return false

	for key in _DEFAULTS.keys():
		var path: String = "%s/%s.bin" % [SANITIZED_DIR, key]
		if not FileAccess.file_exists(path):
			print("[STD] manifest sig matches but missing bin: %s" % path)
			return false

	return true


func _write_dataset_bin(key: String, value: Variant) -> void:
	var path: String = "%s/%s.bin" % [SANITIZED_DIR, key]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not f:
		push_warning("StaticData: failed to open %s for write" % path)
		return
	f.store_buffer(var_to_bytes(value))
	f.close()


func _write_manifest(signature: String) -> void:
	if signature == "":
		return
	var f: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if not f:
		return
	f.store_string(signature)
	f.close()


func _ensure_sanitized_dir() -> void:
	var data_dir: DirAccess = DirAccess.open("user://")
	if data_dir and not data_dir.dir_exists("data"):
		data_dir.make_dir("data")
	var sub: DirAccess = DirAccess.open("user://data")
	if sub and not sub.dir_exists("sanitized"):
		sub.make_dir("sanitized")


func _cleanup_legacy_monolithic_cache() -> void:
	# Old single-blob cache files from before the per-dataset split. Safe to
	# delete unconditionally — even if the manifest isn't valid yet, the cold
	# path will rebuild from JSONs.
	if FileAccess.file_exists(LEGACY_MONOLITHIC_BIN):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_MONOLITHIC_BIN))
	if FileAccess.file_exists(LEGACY_MONOLITHIC_SIG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_MONOLITHIC_SIG))


# === Baked-snapshot seeding (for PCK-shipped first-run cache) ===

func _seed_user_cache_from_baked() -> void:
	# Copies per-dataset baked bins shipped in the PCK into user://data/sanitized/
	# and writes a manifest matching the device's own bundled file versions.
	#
	# Bake workflow (run once on desktop after data changes):
	#   1. Delete <user_data_dir>/data/sanitized/ to force the cold path.
	#   2. Launch the project once; cold path writes 19 per-dataset bins.
	#   3. Copy <user_data_dir>/data/sanitized/*.bin into
	#      godot/baked_static_cache/sanitized/ (do NOT copy manifest.txt — the
	#      device re-derives it from its own bundled JSON sizes).
	#   4. Commit and re-export the Android assets PCK.
	if not DirAccess.dir_exists_absolute(BAKED_SANITIZED_DIR):
		return

	_ensure_sanitized_dir()

	var dir: DirAccess = DirAccess.open(BAKED_SANITIZED_DIR)
	if not dir:
		return

	dir.list_dir_begin()
	var copied: int = 0
	while true:
		var name: String = dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		if not name.ends_with(".bin"):
			continue
		var src: String = "%s/%s" % [BAKED_SANITIZED_DIR, name]
		var dst: String = "%s/%s" % [SANITIZED_DIR, name]
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(src)
		if bytes.is_empty():
			continue
		var out: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
		if not out:
			continue
		out.store_buffer(bytes)
		out.close()
		copied += 1
	dir.list_dir_end()

	if copied == 0:
		return

	var device_sig: String = build_signature()
	_write_manifest(device_sig)
	print("[STD] Seeded user:// per-dataset cache from baked snapshot (%d files)" % copied)


# === Misc ===

func _normalize_limitburst_effects_raw() -> void:
	var limitbursts: Variant = _loaded.get("limitbursts", null)
	if not (limitbursts is Dictionary):
		return
	for limitburst_id in limitbursts.keys():
		var limitburst_data: Variant = limitbursts.get(limitburst_id, {})
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
		limitbursts[limitburst_id] = limitburst_dict


func _notify_skill_resolver() -> void:
	# SkillResolver loads opcode schemas after data is in place. Resolved by
	# autoload name; safe at runtime because prime_cache() is invoked deferred
	# from DataManager._ready, after all autoloads are constructed.
	var resolver: Node = get_node_or_null("/root/SkillResolver")
	if resolver and resolver.has_method("load_schemas"):
		resolver.load_schemas()
