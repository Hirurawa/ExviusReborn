extends Node
## Persistence — owns local snapshot I/O, save index, scoping and legacy migration.
##
## State previously held by DataManager that now lives here:
##   - _save_store (the LocalSaveStore RefCounted)
##   - active_local_save_id (per-account file scope)
##
## DataManager keeps thin delegating wrappers for back-compat; new code should
## call this autoload directly.

const COMBAT_ITEMS_SNAPSHOT_FILE: String = "combat_items.json"
const PARTIES_SNAPSHOT_FILE: String = "parties.json"
const MISSION_PROGRESS_SNAPSHOT_FILE: String = "mission_progress.json"
const ITEMS_SNAPSHOT_FILE: String = "items.json"
const STATS_SNAPSHOT_FILE: String = "stats.json"
const UNITS_SNAPSHOT_FILE: String = "units.json"
const ESPERS_SNAPSHOT_FILE: String = "espers.json"
const SWITCHES_SNAPSHOT_FILE: String = "switches.json"
const LOCAL_SAVE_INDEX_PATH: String = "user://game_state/save_index.json"

const ALL_DOMAIN_SNAPSHOT_FILES: Array[String] = [
	STATS_SNAPSHOT_FILE,
	ITEMS_SNAPSHOT_FILE,
	COMBAT_ITEMS_SNAPSHOT_FILE,
	UNITS_SNAPSHOT_FILE,
	ESPERS_SNAPSHOT_FILE,
	PARTIES_SNAPSHOT_FILE,
	MISSION_PROGRESS_SNAPSHOT_FILE,
	SWITCHES_SNAPSHOT_FILE,
]

var active_local_save_id: String = "default"

var _save_store: RefCounted = null


func _ready() -> void:
	var save_store_script: GDScript = preload("res://core/local_save_store.gd")
	_save_store = save_store_script.new()


# === Snapshot I/O ===

func save_snapshot(file_name: String, payload: Dictionary, source_event: String) -> void:
	if _save_store == null:
		return

	var scoped_file_name: String = get_scoped_snapshot_file_name(file_name)
	var ok: bool = _save_store.save_snapshot(scoped_file_name, payload, source_event)
	if not ok:
		push_warning("Save snapshot failed for %s" % scoped_file_name)


func load_snapshot(file_name: String) -> Dictionary:
	if _save_store == null:
		return {}

	return _save_store.load_snapshot(get_scoped_snapshot_file_name(file_name))


func save_many(payloads_by_file: Dictionary, source_event: String) -> void:
	for file_name in payloads_by_file.keys():
		var payload_variant: Variant = payloads_by_file[file_name]
		if payload_variant is Dictionary:
			save_snapshot(String(file_name), payload_variant, source_event)


# === Save scope / id management ===

func get_scoped_snapshot_file_name(file_name: String) -> String:
	var normalized_save_id: String = normalize_local_save_id(active_local_save_id)
	if normalized_save_id == "":
		normalized_save_id = "default"
	return "%s__%s" % [normalized_save_id, file_name]


func normalize_local_save_id(raw_name: String) -> String:
	var name: String = raw_name.strip_edges().to_lower()
	if name == "":
		return ""

	name = name.replace("/", "_")
	name = name.replace("\\", "_")
	name = name.replace(":", "_")
	name = name.replace("*", "_")
	name = name.replace("?", "_")
	name = name.replace('"', "_")
	name = name.replace("<", "_")
	name = name.replace(">", "_")
	name = name.replace("|", "_")
	name = name.replace(" ", "_")
	while name.find("__") != -1:
		name = name.replace("__", "_")

	if name.begins_with("."):
		name = name.substr(1)
	if name == "":
		name = "default"

	if name.length() > 48:
		name = name.substr(0, 48)

	return name


func set_active_save(username: String) -> String:
	var save_id: String = find_save_id_for_username(username)
	if save_id == "":
		save_id = normalize_local_save_id(username)
	active_local_save_id = save_id
	return save_id


# === Save index ===

func ensure_game_state_dir() -> void:
	if DirAccess.dir_exists_absolute("user://game_state"):
		return
	DirAccess.make_dir_recursive_absolute("user://game_state")


func load_save_index() -> Dictionary:
	ensure_game_state_dir()
	if not FileAccess.file_exists(LOCAL_SAVE_INDEX_PATH):
		return {"saves": []}

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCAL_SAVE_INDEX_PATH))
	if not (parsed is Dictionary):
		return {"saves": []}

	var index_data: Dictionary = parsed
	if not index_data.has("saves") or not (index_data["saves"] is Array):
		index_data["saves"] = []

	return index_data


func save_save_index(index_data: Dictionary) -> void:
	ensure_game_state_dir()
	var file: FileAccess = FileAccess.open(LOCAL_SAVE_INDEX_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to write local save index")
		return
	file.store_string(JSON.stringify(index_data, "\t"))
	file.close()


func list_local_saves() -> Array:
	var index_data: Dictionary = load_save_index()
	var saves_variant: Variant = index_data.get("saves", [])
	if saves_variant is Array:
		return (saves_variant as Array).duplicate(true)
	return []


func upsert_save_index_entry(save_id: String, username: String) -> void:
	var index_data: Dictionary = load_save_index()
	var saves: Array = index_data.get("saves", [])
	var now_unix: int = int(Time.get_unix_time_from_system())
	var found_index: int = -1
	for i in range(saves.size()):
		var entry: Variant = saves[i]
		if entry is Dictionary and str(entry.get("id", "")) == save_id:
			found_index = i
			break

	if found_index >= 0:
		var existing: Dictionary = saves[found_index]
		existing["username"] = username
		existing["last_loaded_unix"] = now_unix
		saves[found_index] = existing
	else:
		saves.append({
			"id": save_id,
			"username": username,
			"created_at_unix": now_unix,
			"last_loaded_unix": now_unix
		})

	index_data["saves"] = saves
	save_save_index(index_data)


func find_save_id_for_username(username: String) -> String:
	var target: String = username.strip_edges().to_lower()
	if target == "":
		return ""

	for entry_var in list_local_saves():
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var
		if str(entry.get("username", "")).strip_edges().to_lower() == target:
			return str(entry.get("id", ""))

	return ""


func get_most_recent_save() -> Dictionary:
	var best: Dictionary = {}
	var best_ts: int = -1
	for entry_var in list_local_saves():
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var
		var ts: int = int(entry.get("last_loaded_unix", entry.get("created_at_unix", 0)))
		if ts > best_ts:
			best_ts = ts
			best = entry
	return best


func delete_local_save(save_id: String) -> bool:
	var trimmed_id: String = save_id.strip_edges()
	if trimmed_id == "":
		return false

	ensure_game_state_dir()
	var dir: DirAccess = DirAccess.open("user://game_state")
	if dir != null:
		for file_name in ALL_DOMAIN_SNAPSHOT_FILES:
			var scoped_name: String = "%s__%s" % [trimmed_id, file_name]
			if dir.file_exists(scoped_name):
				var err: Error = dir.remove(scoped_name)
				if err != OK:
					push_warning("delete_local_save: failed to remove %s (err %d)" % [scoped_name, err])

	var index_data: Dictionary = load_save_index()
	var saves: Array = index_data.get("saves", [])
	var filtered: Array = []
	var removed: bool = false
	for entry_var in saves:
		if entry_var is Dictionary and str((entry_var as Dictionary).get("id", "")) == trimmed_id:
			removed = true
			continue
		filtered.append(entry_var)
	if removed:
		index_data["saves"] = filtered
		save_save_index(index_data)

	if active_local_save_id == trimmed_id:
		active_local_save_id = "default"

	return removed


# === Legacy (pre-scoped) snapshot migration ===

func legacy_snapshot_exists() -> bool:
	if _save_store == null:
		return false
	return not _save_store.load_snapshot(STATS_SNAPSHOT_FILE).is_empty()


func migrate_legacy_snapshots_to_active_save() -> void:
	if _save_store == null:
		return

	for file_name in ALL_DOMAIN_SNAPSHOT_FILES:
		var legacy_envelope: Dictionary = _save_store.load_snapshot(file_name)
		if legacy_envelope.is_empty():
			continue
		var legacy_payload: Variant = legacy_envelope.get("data", {})
		if not (legacy_payload is Dictionary):
			continue
		_save_store.save_snapshot(get_scoped_snapshot_file_name(file_name), legacy_payload, "legacy_migration")
