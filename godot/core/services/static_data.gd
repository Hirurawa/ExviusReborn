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
const KEYS_INDEX_PATH: String = "user://data/sanitized/keys_index.bin"
# Flat layout: baked per-dataset bins live directly under res://baked_static_cache/
# (previously a non-existent /sanitized/ subdir was referenced here, which silently
# disabled first-launch seeding on Android and forced the cold path → OOM crashes).
const BAKED_SANITIZED_DIR: String = "res://baked_static_cache"

# Datasets whose top-level keys are queried by `.has()` in hot paths (stat calc,
# skill classification, etc.) but whose full Variant trees are huge. A side
# `keys_index.bin` caches just the key sets so those checks don't force-decode
# the full dataset. Lazy-decoded once and reused across launches.
const KEY_INDEXED_DATASETS: Array[String] = [
	"skills_magic", "skills_ability", "skills_passive",
	"equipment", "materia", "limitbursts", "summons",
]

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

# Per-dataset key sets, populated by `_ensure_keys_index_loaded`. Each value is
# a Dictionary used as a set (id_string -> true). Lets hot paths do
# `dataset_has(key, id)` without forcing a full dataset decode.
var _keys_index: Dictionary = {}
var _keys_index_loaded: bool = false


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
		_ensure_keys_index_loaded()
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

	# If the per-dataset cache is already verified, we're fine. Otherwise check
	# that a signature is derivable AND that every .bin exists. We no longer
	# require user://data/*.json to exist, since we stopped mirroring JSONs.
	if _signature_valid:
		return false

	var sig: String = build_signature()
	if sig == "":
		return true
	return not _per_dataset_caches_valid(sig)


# === Eviction API ===

func evict_dataset(key: String) -> void:
	_loaded.erase(key)
	if key == "monsters":
		_monsters_by_name.clear()


func evict_all() -> void:
	_loaded.clear()
	_monsters_by_name.clear()
	# Keep _keys_index — it's tiny and we rebuild from disk if needed.


# Caller-friendly batch evictions. Scenes that know they're done with a set of
# datasets can call these to drop them; they will reload lazily if anyone
# touches them again.
func evict_outgame_only_datasets() -> void:
	for k in ["summons_boards", "summons_exp_patterns", "summons_stat_patterns",
			"equipment-icons", "unit_exp_patterns", "worlds", "towns"]:
		_loaded.erase(k)


# Side-index over the monsters Array (which is stored as an Array, not a dict).
# Built lazily on first call; rebuilt after `evict_dataset("monsters")`. Avoids
# the O(n) scan in `battle_manager._generate_enemy_data` on every spawn.
var _monsters_by_name: Dictionary = {}

func get_monster_by_name(name: String) -> Dictionary:
	if name == "":
		return {}
	if _monsters_by_name.is_empty():
		var arr: Variant = _ensure_dataset("monsters")
		if not (arr is Array):
			return {}
		for monster in arr:
			if monster is Dictionary:
				var n: String = str(monster.get("name", ""))
				if n != "":
					_monsters_by_name[n] = monster
	var hit: Variant = _monsters_by_name.get(name, null)
	if hit is Dictionary:
		return hit
	return {}


# === Lightweight keys-only index ===
#
# Many hot paths (stat_calculator, battle_ui) only need to know whether an id
# is present in skills_magic/skills_ability/skills_passive/equipment/materia/
# limitbursts/summons. Calling `.has()` via the property bridge forces a full
# Variant decode of the dataset (≥200 MB for skills_ability alone). The keys
# index keeps a tiny `{id: true}` set per dataset, persisted to disk, so
# `dataset_has()` runs without touching the dataset payload.

func dataset_has(dataset_key: String, id: String) -> bool:
	if id == "":
		return false
	_ensure_keys_index_loaded()
	var set_d: Variant = _keys_index.get(dataset_key, null)
	if set_d is Dictionary:
		return (set_d as Dictionary).has(id)
	# Fallback: dataset wasn't indexed (legacy cache). Decode lazily.
	var ds: Variant = _ensure_dataset(dataset_key)
	if ds is Dictionary:
		return (ds as Dictionary).has(id)
	return false


func classify_skill_id(id: String) -> String:
	# Returns "magic", "ability", "passive", or "" if unknown. Used by
	# stat_calculator instead of three chained `.has()` calls that each used
	# to force-decode a 30+ MB skill dataset.
	if id == "":
		return ""
	_ensure_keys_index_loaded()
	if _keys_index.get("skills_magic", {}).has(id):
		return "magic"
	if _keys_index.get("skills_ability", {}).has(id):
		return "ability"
	if _keys_index.get("skills_passive", {}).has(id):
		return "passive"
	return ""


func _ensure_keys_index_loaded() -> void:
	if _keys_index_loaded:
		return
	# Try the persisted on-disk index first.
	if FileAccess.file_exists(KEYS_INDEX_PATH):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(KEYS_INDEX_PATH)
		if not bytes.is_empty():
			var decoded: Variant = bytes_to_var(bytes)
			if decoded is Dictionary:
				_keys_index = decoded
				_keys_index_loaded = true
				return
	# No persisted index — build it now from .bin files on disk. We avoid the
	# property bridge so this doesn't pin the full datasets in `_loaded`.
	_build_keys_index_from_disk()
	_keys_index_loaded = true
	_write_keys_index()


func _build_keys_index_from_loaded() -> void:
	_keys_index.clear()
	for key in KEY_INDEXED_DATASETS:
		var ds: Variant = _loaded.get(key, null)
		_keys_index[key] = _extract_keys_set(ds)
	_keys_index_loaded = true


func _build_keys_index_from_disk() -> void:
	_keys_index.clear()
	for key in KEY_INDEXED_DATASETS:
		var ds: Variant = _load_dataset_from_disk(key)
		_keys_index[key] = _extract_keys_set(ds)
		# Drop the decoded copy immediately — we only needed its keys. The
		# dataset will reload lazily on first real `.get()` access.


func _extract_keys_set(ds: Variant) -> Dictionary:
	var s: Dictionary = {}
	if ds is Dictionary:
		for k in (ds as Dictionary).keys():
			s[str(k)] = true
	return s


func _write_keys_index() -> void:
	if _keys_index.is_empty():
		return
	var f: FileAccess = FileAccess.open(KEYS_INDEX_PATH, FileAccess.WRITE)
	if not f:
		return
	f.store_buffer(var_to_bytes(_keys_index))
	f.close()


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
	# Streaming cold path: for each dataset, parse JSON → sanitize in place →
	# write .bin → keep in `_loaded` for this session. Yields between files so
	# the main thread can render the busy UI and Android doesn't ANR.
	_dbg_mem("cold_path enter")
	var cache_signature: String = build_signature()

	# If a valid per-dataset cache already exists on disk (e.g. baked or from a
	# previous run), skip the sanitize + rewrite step entirely.
	if cache_signature != "" and _per_dataset_caches_valid(cache_signature):
		_dbg_mem("per-dataset cache already valid, no rewrite")
		_signature_valid = true
		_notify_skill_resolver()
		return false

	_ensure_sanitized_dir()

	for prop_name in _PROP_TO_KEY.keys():
		var key: String = _PROP_TO_KEY[prop_name]
		StaticDataLoader.patch_progress.emit(key, "Loading...")
		var parsed: Variant = StaticDataLoader.load_one(key)
		if parsed == null:
			push_warning("StaticData: cold path could not parse '%s'; using default" % key)
			parsed = _default_for(key)
		# In-place sanitize avoids a deep duplicate of the parsed tree.
		_sanitize_floats_to_ints_inplace(parsed)
		_loaded[key] = parsed
		_write_dataset_bin(key, parsed)
		_dbg_mem("sanitized+wrote %s" % key)
		# Yield one frame so the engine can run GC, paint the progress UI, and
		# avoid Android Watchdog ANR on the biggest files.
		await get_tree().process_frame

	if _loaded.has("limitbursts"):
		_normalize_limitburst_effects_raw()

	# Build the lightweight keys index from the now-resident dictionaries
	# before we drop them; persists to disk so subsequent launches don't have
	# to decode the big skill/equipment dicts just to populate it.
	_build_keys_index_from_loaded()
	_write_keys_index()

	_write_manifest(cache_signature)
	_signature_valid = true
	_notify_skill_resolver()
	_dbg_mem("cold_path exit")
	return false


func _dbg_mem(tag: String) -> void:
	if not OS.is_debug_build():
		return
	var mb: float = float(OS.get_static_memory_usage()) / 1048576.0
	print("[STD] %-40s static=%.1fMB" % [tag, mb])


# === Sanitization ===

func _sanitize_floats_to_ints_inplace(data: Variant) -> void:
	# Mutates the tree in place: replaces float values that are whole numbers
	# with their int equivalents. Roughly halves cold-path peak vs. the old
	# deep-duplicating variant; avoids unnecessary allocation for subtrees that
	# contain no floats at all.
	if typeof(data) == TYPE_DICTIONARY:
		var d: Dictionary = data
		for k in d.keys():
			var v: Variant = d[k]
			var t: int = typeof(v)
			if t == TYPE_FLOAT:
				if fmod(v, 1.0) == 0.0:
					d[k] = int(v)
			elif t == TYPE_DICTIONARY or t == TYPE_ARRAY:
				_sanitize_floats_to_ints_inplace(v)
	elif typeof(data) == TYPE_ARRAY:
		var a: Array = data
		for i in range(a.size()):
			var v: Variant = a[i]
			var t: int = typeof(v)
			if t == TYPE_FLOAT:
				if fmod(v, 1.0) == 0.0:
					a[i] = int(v)
			elif t == TYPE_DICTIONARY or t == TYPE_ARRAY:
				_sanitize_floats_to_ints_inplace(v)


func sanitize_floats_to_ints(data: Variant) -> Variant:
	# Retained for external callers (skill resolver, tests). Internally we use
	# the in-place variant for memory reasons.
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
		# Invalidate the keys index too; it must be rebuilt from the new
		# datasets after the cold path writes them.
		if FileAccess.file_exists(KEYS_INDEX_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(KEYS_INDEX_PATH))
		_keys_index.clear()
		_keys_index_loaded = false
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
	#      godot/baked_static_cache/ (flat layout — do NOT include a `sanitized/`
	#      subdir, and do NOT copy manifest.txt; the device re-derives the
	#      manifest from its own bundled JSON sizes). Include `keys_index.bin`
	#      if present — seeding it avoids decoding heavy skill/equipment
	#      datasets on Android first-launch just to compute their key sets.
	#   4. Commit and re-export the Android assets PCK.
	if not DirAccess.dir_exists_absolute(BAKED_SANITIZED_DIR):
		print("[STD] baked dir missing: %s (will fall through to cold path)" % BAKED_SANITIZED_DIR)
		return

	_ensure_sanitized_dir()

	var dir: DirAccess = DirAccess.open(BAKED_SANITIZED_DIR)
	if not dir:
		print("[STD] could not open baked dir: %s" % BAKED_SANITIZED_DIR)
		return

	dir.list_dir_begin()
	var copied: int = 0
	var skipped: int = 0
	while true:
		var name: String = dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		if not name.ends_with(".bin"):
			continue
		# Only copy bins that correspond to a known dataset key; this guards
		# against legacy/unrelated bins (e.g. the old monolithic
		# sanitized_data_cache.bin) being dragged into user://.
		var key: String = name.get_basename()
		var is_keys_index: bool = (name == "keys_index.bin")
		if not is_keys_index and not _DEFAULTS.has(key):
			skipped += 1
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
		print("[STD] baked dir present but no dataset bins copied (skipped=%d)" % skipped)
		return

	var device_sig: String = build_signature()
	_write_manifest(device_sig)
	var expected: int = _DEFAULTS.size()
	if copied < expected:
		push_warning("StaticData: seeded only %d/%d baked bins; cold path may still run" % [copied, expected])
	print("[STD] Seeded user:// per-dataset cache from baked snapshot (%d/%d files, skipped=%d)" % [copied, expected, skipped])


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
