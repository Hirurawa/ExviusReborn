extends Node

signal data_loaded
signal login_success
signal login_failed(error_code: int)
signal register_success
signal register_failed(error_code: int)
signal account_updated(username: String)
signal rank_updated(rank: int, xp: int, next_rank_xp: int)
signal nrg_updated(current_nrg: int, max_nrg: int, time_until_next: float)
signal currency_updated(gil: int, lapis: int)
signal units_updated(units: Array)
signal items_updated(items: Dictionary)
signal combat_items_updated(slots: Array)
signal combat_items_loaded(slots: Array)
signal combat_items_saved(slots: Array)
signal friends_updated(friends: Object)
signal friend_action_result(success: bool, message: String)
signal parties_updated(parties: Array)
signal party_save_requested(new_parties: Array)
signal active_party_changed(party_index: int)
signal purchase_successful()
signal purchase_failed(error_message: String)

signal dungeon_missions_ready(mission_ids: Array)
signal mission_completed(rewards_text: String)
signal mission_failed(error_msg: String)
signal equip_successful()
signal equip_failed(error_message: String)
signal mission_progress_loaded(latest_mission_id: String)

var _save_store: RefCounted = null

var current_rank: int = 1
var current_xp: int = 0
var next_rank_xp: int = 100
var current_nrg: int = 0
var max_nrg: int = 0
var nrg_regen_rate_seconds: int = 300
var seconds_until_next_nrg: float = 0.0
var last_entered_mission_id: String = ""

var gil: int = 0
var lapis: int = 0
var current_username: String = ""

var owned_units_ids: Array = []

var last_played_dungeon_name: String = ""
var cleared_missions: Dictionary = {}
var latest_cleared_mission_id: String = ""
var owned_items: Dictionary = {"stackables": {}, "equipment": []}
const COMBAT_ITEM_SLOT_COUNT: int = 10
const COMBAT_ITEMS_SNAPSHOT_FILE: String = "combat_items.json"
const PARTIES_SNAPSHOT_FILE: String = "parties.json"
const MISSION_PROGRESS_SNAPSHOT_FILE: String = "mission_progress.json"
const ITEMS_SNAPSHOT_FILE: String = "items.json"
const STATS_SNAPSHOT_FILE: String = "stats.json"
const UNITS_SNAPSHOT_FILE: String = "units.json"
const LOCAL_SAVE_INDEX_PATH: String = "user://game_state/save_index.json"
const STARTER_RAIN_UNIT_ID: String = "100000102"
const STARTER_LASSWELL_UNIT_ID: String = "100000202"
const STARTER_RAIN_INSTANCE_ID: String = "starter_100000102"
const STARTER_LASSWELL_INSTANCE_ID: String = "starter_100000202"
var combat_items: Array = ["", "", "", "", "", "", "", "", "", ""]
var parties: Array = []
var selected_party_index: int = 0
var active_local_save_id: String = "default"

var game_data_units: Dictionary = {}
var game_data_items: Dictionary = {}
var game_data_equipment: Dictionary = {}
var game_data_worlds: Dictionary = {}
var game_data_dungeons: Dictionary = {}
var game_data_missions: Dictionary = {}
var game_data_skills_magic: Dictionary = {}
var game_data_skills_ability: Dictionary = {}
var game_data_skills_passive: Dictionary = {}
var game_data_limitbursts: Dictionary = {}
var game_data_materia: Dictionary = {}
var game_data_equipment_icons: Dictionary = {}
var game_data_monsters = []
var game_data_summons: Dictionary = {}
var game_data_summons_boards: Dictionary = {}
var game_data_summons_exp_patterns: Dictionary = {}
var game_data_summons_stat_patterns: Dictionary = {}
var opcode_skill_schema: Dictionary = {}
var opcode_passive_schema: Dictionary = {}
var opcode_schemas_ready: bool = false
var opcode_schema_error: String = ""

const ENHANCE_MAX_TRUST_VALUE: float = 100.0
const ENHANCE_GIL_COST_PER_MATERIAL: int = 1000
const ENHANCE_BASE_XP_GAIN: int = 100
const ENHANCE_XP_PER_RARITY: int = 100
const ENHANCE_XP_PER_LEVEL: int = 20
const ENHANCE_BASE_TRUST_GAIN: float = 0.2
const ENHANCE_TRUST_PER_RARITY: float = 0.15
const ENHANCE_TRUST_PER_LEVEL: float = 0.01
const UNIT_TYPE_PLAYABLE: String = "playable"
const UNIT_TYPE_EXP_MATERIAL: String = "exp_material"
const UNIT_TYPE_TRUST_MATERIAL: String = "trust_material"
const PLAYABLE_ACCUMULATED_EXP_TRANSFER_RATE: float = 0.5
const PLAYABLE_DUPLICATE_TRUST_BONUS: float = 5.0
const DEFAULT_MAX_ACCUMULATED_EXP: int = 2000000000
const EXP_UNIT_JOB_ID: int = 901
const TRUST_MATERIAL_JOB_ID: int = 903
const EXP_UNIT_YIELD_BY_PATTERN: Dictionary = {
	201: 5000,
	202: 10000,
	203: 30000,
	204: 100000,
}
const TRUST_YIELD_BY_UNIT_ID: Dictionary = {
	904000101: 1.0,
	904000104: 5.0,
	904000105: 10.0,
}
var _unit_exp_patterns_cache: Dictionary = {}

const OPCODE_SKILL_SCHEMA_PATH: String = "res://features/battle/logic/skill_schema.json"
const OPCODE_PASSIVE_SCHEMA_PATH: String = "res://features/battle/logic/passive_schema.json"

var account_info = null
var _static_data_ready: bool = false
var _static_data_loading: bool = false
var _static_data_synced_with_server: bool = false
var _static_data_sync_queued: bool = false

signal _static_data_primed

func _ready() -> void:
	var save_store_script: GDScript = preload("res://core/local_save_store.gd")
	_save_store = save_store_script.new()

	party_save_requested.connect(save_parties)
	call_deferred("_prime_static_data_cache")

func _process(delta: float) -> void:
	if max_nrg > 0 and current_nrg < max_nrg:
		seconds_until_next_nrg -= delta
		if seconds_until_next_nrg <= 0:
			current_nrg += 1
			seconds_until_next_nrg = nrg_regen_rate_seconds
			nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
		else:
			# Still ticking, UI might want to know for the timer
			nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)

func authenticate(email: String, password: String) -> void:
	await _load_initial_data(email)
	login_success.emit()

func register(email: String, password: String, username: String) -> void:
	await _load_initial_data(email)
	register_success.emit()

func logout() -> void:
	account_info = null
	_static_data_synced_with_server = false
	_static_data_sync_queued = false
	last_entered_mission_id = ""
	last_played_dungeon_name = ""
	selected_party_index = 0

func _save_snapshot(file_name: String, payload: Dictionary, source_event: String) -> void:
	if _save_store == null:
		return

	var scoped_file_name: String = _get_scoped_snapshot_file_name(file_name)
	var ok: bool = _save_store.save_snapshot(scoped_file_name, payload, source_event)
	if not ok:
		push_warning("Save snapshot failed for %s" % scoped_file_name)

func _load_snapshot(file_name: String) -> Dictionary:
	if _save_store == null:
		return {}

	return _save_store.load_snapshot(_get_scoped_snapshot_file_name(file_name))

func _get_scoped_snapshot_file_name(file_name: String) -> String:
	var normalized_save_id: String = _normalize_local_save_id(active_local_save_id)
	if normalized_save_id == "":
		normalized_save_id = "default"
	return "%s__%s" % [normalized_save_id, file_name]

func _normalize_local_save_id(raw_name: String) -> String:
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

func _ensure_game_state_dir() -> void:
	if DirAccess.dir_exists_absolute("user://game_state"):
		return
	DirAccess.make_dir_recursive_absolute("user://game_state")

func _load_local_save_index() -> Dictionary:
	_ensure_game_state_dir()
	if not FileAccess.file_exists(LOCAL_SAVE_INDEX_PATH):
		return {"saves": []}

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCAL_SAVE_INDEX_PATH))
	if not (parsed is Dictionary):
		return {"saves": []}

	var index_data: Dictionary = parsed
	if not index_data.has("saves") or not (index_data["saves"] is Array):
		index_data["saves"] = []

	return index_data

func _save_local_save_index(index_data: Dictionary) -> void:
	_ensure_game_state_dir()
	var file: FileAccess = FileAccess.open(LOCAL_SAVE_INDEX_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to write local save index")
		return
	file.store_string(JSON.stringify(index_data, "\t"))
	file.close()

func list_local_saves() -> Array:
	var index_data: Dictionary = _load_local_save_index()
	var saves_variant: Variant = index_data.get("saves", [])
	if saves_variant is Array:
		return (saves_variant as Array).duplicate(true)
	return []

func _upsert_local_save_index_entry(save_id: String, username: String) -> void:
	var index_data: Dictionary = _load_local_save_index()
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
	_save_local_save_index(index_data)

func _find_save_id_for_username(username: String) -> String:
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

func _legacy_snapshot_exists() -> bool:
	if _save_store == null:
		return false
	return not _save_store.load_snapshot(STATS_SNAPSHOT_FILE).is_empty()

func _migrate_legacy_snapshots_to_active_save() -> void:
	if _save_store == null:
		return

	var snapshot_files: Array[String] = [
		STATS_SNAPSHOT_FILE,
		ITEMS_SNAPSHOT_FILE,
		COMBAT_ITEMS_SNAPSHOT_FILE,
		UNITS_SNAPSHOT_FILE,
		PARTIES_SNAPSHOT_FILE,
		MISSION_PROGRESS_SNAPSHOT_FILE
	]

	for file_name in snapshot_files:
		var legacy_envelope: Dictionary = _save_store.load_snapshot(file_name)
		if legacy_envelope.is_empty():
			continue
		var legacy_payload: Variant = legacy_envelope.get("data", {})
		if not (legacy_payload is Dictionary):
			continue
		_save_store.save_snapshot(_get_scoped_snapshot_file_name(file_name), legacy_payload, "legacy_migration")

func _set_active_local_save(username: String) -> String:
	var save_id: String = _find_save_id_for_username(username)
	if save_id == "":
		save_id = _normalize_local_save_id(username)
	active_local_save_id = save_id
	return save_id

func _build_starter_unit_local(unit_id: String, instance_id: String) -> Dictionary:
	var unit_data: Dictionary = game_data_units.get(unit_id, {})
	if unit_data.is_empty():
		return {}

	var initial_rarity: int = _get_unit_initial_rarity(unit_id)
	var exp_pattern: int = _get_raw_unit_exp_pattern(unit_id, unit_data, initial_rarity)
	if exp_pattern <= 0:
		exp_pattern = 5
	var next_xp_required: int = _calculate_xp_for_level_local(2, exp_pattern)
	if next_xp_required <= 0:
		next_xp_required = 1000

	return {
		"instance_id": instance_id,
		"unit_id": unit_id,
		"level": 1,
		"xp": 0,
		"current_rarity": initial_rarity,
		"next_xp": next_xp_required,
		"equipment": {},
		"trust_value": 0,
		"limitburst_level": 1,
		"limitburst_xp": 0,
		"is_locked": false,
		"trust_reward_claimed": false,
		"current_accumulated_exp": 0
	}

func _build_default_parties_local(rain_instance_id: String, lasswell_instance_id: String) -> Array:
	var generated_parties: Array = []
	for i in range(5):
		generated_parties.append({
			"name": "Party %d" % (i + 1),
			"units": ["", "", "", "", ""]
		})

	if not generated_parties.is_empty():
		generated_parties[0]["units"][0] = rain_instance_id
		generated_parties[0]["units"][1] = lasswell_instance_id

	return generated_parties

func start_new_local_game(username: String) -> Dictionary:
	var normalized_username: String = username.strip_edges()
	if normalized_username == "":
		return {"success": false, "error_message": "Please enter a save name."}

	await _ensure_static_data_ready()
	active_local_save_id = _normalize_local_save_id(normalized_username)

	var rain_unit: Dictionary = _build_starter_unit_local(STARTER_RAIN_UNIT_ID, STARTER_RAIN_INSTANCE_ID)
	var lasswell_unit: Dictionary = _build_starter_unit_local(STARTER_LASSWELL_UNIT_ID, STARTER_LASSWELL_INSTANCE_ID)
	if rain_unit.is_empty() or lasswell_unit.is_empty():
		return {"success": false, "error_message": "Failed to initialize starter units."}

	current_rank = 1
	current_xp = 0
	next_rank_xp = 100
	current_nrg = 41
	max_nrg = 41
	nrg_regen_rate_seconds = 300
	seconds_until_next_nrg = 0.0
	last_entered_mission_id = ""
	last_played_dungeon_name = ""
	gil = 0
	lapis = 0
	current_username = normalized_username
	account_info = null

	owned_items = {"stackables": {}, "equipment": []}
	combat_items = ["", "", "", "", "", "", "", "", "", ""]
	cleared_missions = {}
	latest_cleared_mission_id = ""
	owned_units_ids = _hydrate_owned_units([rain_unit, lasswell_unit])
	parties = _build_default_parties_local(STARTER_RAIN_INSTANCE_ID, STARTER_LASSWELL_INSTANCE_ID)
	selected_party_index = 0

	_save_all_snapshots("new_local_game")
	_upsert_local_save_index_entry(active_local_save_id, current_username)

	rank_updated.emit(current_rank, current_xp, next_rank_xp)
	nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
	currency_updated.emit(gil, lapis)
	items_updated.emit(owned_items)
	combat_items_loaded.emit(combat_items.duplicate())
	units_updated.emit(owned_units_ids)
	parties_updated.emit(parties)
	active_party_changed.emit(selected_party_index)
	account_updated.emit(current_username)
	data_loaded.emit()

	return {"success": true, "save_id": active_local_save_id}

func load_local_game(username: String) -> Dictionary:
	var normalized_username: String = username.strip_edges()
	if normalized_username == "":
		return {"success": false, "error_message": "Please enter a save name."}

	await _ensure_static_data_ready()
	var resolved_save_id: String = _set_active_local_save(normalized_username)

	var envelope: Dictionary = _load_snapshot(STATS_SNAPSHOT_FILE)
	if envelope.is_empty() and _legacy_snapshot_exists():
		_migrate_legacy_snapshots_to_active_save()
		envelope = _load_snapshot(STATS_SNAPSHOT_FILE)

	if envelope.is_empty():
		return {"success": false, "error_message": "No save found with that name."}

	await _load_initial_data(normalized_username)
	_upsert_local_save_index_entry(resolved_save_id, current_username if current_username != "" else normalized_username)
	return {"success": true, "save_id": resolved_save_id}

func _snapshot_stats_payload() -> Dictionary:
	return {
		"rank": current_rank,
		"xp": current_xp,
		"next_rank_xp": next_rank_xp,
		"current_nrg": current_nrg,
		"max_nrg": max_nrg,
		"nrg_regen_rate_seconds": nrg_regen_rate_seconds,
		"seconds_until_next_nrg": seconds_until_next_nrg,
		"last_entered_mission_id": last_entered_mission_id,
		"gil": gil,
		"lapis": lapis,
		"username": current_username
	}

func _snapshot_items_payload() -> Dictionary:
	return {
		"owned_items": owned_items.duplicate(true)
	}

func _snapshot_combat_items_payload() -> Dictionary:
	return {
		"slots": combat_items.duplicate()
	}

func _normalize_combat_items_slots(raw_slots: Variant) -> Array:
	var normalized: Array = ["", "", "", "", "", "", "", "", "", ""]
	if not (raw_slots is Array):
		return normalized

	var source_slots: Array = raw_slots
	for i in range(min(COMBAT_ITEM_SLOT_COUNT, source_slots.size())):
		normalized[i] = str(source_slots[i])

	return normalized

func _load_combat_items_from_local() -> Array:
	if _save_store == null:
		return ["", "", "", "", "", "", "", "", "", ""]

	var envelope: Dictionary = _load_snapshot(COMBAT_ITEMS_SNAPSHOT_FILE)
	if envelope.is_empty():
		return ["", "", "", "", "", "", "", "", "", ""]

	var data: Variant = envelope.get("data", {})
	if not (data is Dictionary):
		return ["", "", "", "", "", "", "", "", "", ""]

	var slots: Variant = data.get("slots", [])
	return _normalize_combat_items_slots(slots)

func _normalize_parties_payload(raw_payload: Variant) -> Dictionary:
	if not (raw_payload is Dictionary):
		return {"parties": [], "selected_party_index": 0}

	var payload: Dictionary = raw_payload
	var local_parties: Array = []
	if payload.has("parties") and payload["parties"] is Array:
		local_parties = payload["parties"].duplicate(true)

	var local_selected: int = int(payload.get("selected_party_index", 0))
	if local_parties.is_empty():
		local_selected = 0
	else:
		local_selected = clampi(local_selected, 0, local_parties.size() - 1)

	return {
		"parties": local_parties,
		"selected_party_index": local_selected
	}

func _load_parties_from_local() -> Dictionary:
	if _save_store == null:
		return {"parties": [], "selected_party_index": 0}

	var envelope: Dictionary = _load_snapshot(PARTIES_SNAPSHOT_FILE)
	if envelope.is_empty():
		return {"parties": [], "selected_party_index": 0}

	var data: Variant = envelope.get("data", {})
	return _normalize_parties_payload(data)

func _snapshot_units_payload() -> Dictionary:
	# Store only lean unit records (persistence data), not hydrated computed state
	var lean_units: Array = []
	for unit in owned_units_ids:
		if unit is Dictionary:
			lean_units.append(_extract_unit_lean_record(unit))
		else:
			lean_units.append(unit)
	return {
		"owned_units": lean_units
	}

func _extract_unit_lean_record(hydrated_unit: Dictionary) -> Dictionary:
	# Extract only the persistence fields that Nakama stores
	return {
		"xp": int(hydrated_unit.get("xp", 0)),
		"level": int(hydrated_unit.get("level", 1)),
		"next_xp": int(hydrated_unit.get("next_xp", 0)),
		"unit_id": str(hydrated_unit.get("unit_id", "")),
		"instance_id": str(hydrated_unit.get("instance_id", "")),
		"equipment": _normalize_unit_equipment(hydrated_unit.get("equipment", {})),
		"is_locked": bool(hydrated_unit.get("is_locked", false)),
		"trust_value": int(hydrated_unit.get("trust_value", 0)),
		"trust_reward_claimed": bool(hydrated_unit.get("trust_reward_claimed", false)),
		"limitburst_xp": int(hydrated_unit.get("limitburst_xp", 0)),
		"limitburst_level": int(hydrated_unit.get("limitburst_level", 1)),
		"current_rarity": int(hydrated_unit.get("current_rarity", 1)),
		"current_accumulated_exp": int(hydrated_unit.get("current_accumulated_exp", 0))
	}

func _snapshot_parties_payload() -> Dictionary:
	return {
		"parties": parties.duplicate(true),
		"selected_party_index": selected_party_index
	}

func _snapshot_mission_progress_payload() -> Dictionary:
	return {
		"cleared_missions": cleared_missions.duplicate(true),
		"latest_cleared_mission_id": latest_cleared_mission_id
	}

func _normalize_units_payload(raw_payload: Variant) -> Array:
	if not (raw_payload is Dictionary):
		return []

	var payload: Dictionary = raw_payload
	var units_list: Variant = payload.get("owned_units", [])
	if not (units_list is Array):
		return []

	var lean_units: Array = []
	for unit in units_list:
		if unit is Dictionary:
			lean_units.append(unit.duplicate(true))
		else:
			lean_units.append(unit)

	return lean_units

func _load_units_from_local() -> Array:
	if _save_store == null:
		return []

	var envelope: Dictionary = _load_snapshot(UNITS_SNAPSHOT_FILE)
	if envelope.is_empty():
		return []

	var data: Variant = envelope.get("data", {})
	if not (data is Dictionary):
		return []

	var lean_units: Array = _normalize_units_payload(data)
	if lean_units.is_empty():
		return []

	# Re-hydrate lean records with current static data and calculated stats
	return _hydrate_owned_units(lean_units)

func _load_mission_progress_from_local() -> Dictionary:
	if _save_store == null:
		return {"cleared_missions": {}, "latest_cleared_mission_id": ""}

	var envelope: Dictionary = _load_snapshot(MISSION_PROGRESS_SNAPSHOT_FILE)
	if envelope.is_empty():
		return {"cleared_missions": {}, "latest_cleared_mission_id": ""}

	var data: Variant = envelope.get("data", {})
	if not (data is Dictionary):
		return {"cleared_missions": {}, "latest_cleared_mission_id": ""}

	var payload: Dictionary = data
	var local_cleared: Dictionary = {}
	if payload.has("cleared_missions") and payload["cleared_missions"] is Dictionary:
		local_cleared = payload["cleared_missions"].duplicate(true)

	var computed_latest: String = _get_latest_cleared_mission_id_from_progress(local_cleared)
	var local_latest: String = str(payload.get("latest_cleared_mission_id", computed_latest))
	if local_latest == "":
		local_latest = computed_latest

	return {
		"cleared_missions": local_cleared,
		"latest_cleared_mission_id": local_latest
	}

func _normalize_items_payload(raw_payload: Variant) -> Dictionary:
	if not (raw_payload is Dictionary):
		return {"stackables": {}, "equipment": []}

	var payload: Dictionary = raw_payload
	var local_stackables: Dictionary = {}
	if payload.has("owned_items") and payload["owned_items"] is Dictionary:
		var items_dict: Dictionary = payload["owned_items"]
		if items_dict.has("stackables") and items_dict["stackables"] is Dictionary:
			local_stackables = items_dict["stackables"].duplicate(true)

	var local_equipment: Array = []
	if payload.has("owned_items") and payload["owned_items"] is Dictionary:
		var items_dict: Dictionary = payload["owned_items"]
		if items_dict.has("equipment") and items_dict["equipment"] is Array:
			local_equipment = items_dict["equipment"].duplicate(true)

	return {
		"stackables": local_stackables,
		"equipment": local_equipment
	}

func _load_items_from_local() -> Dictionary:
	if _save_store == null:
		return {"stackables": {}, "equipment": []}

	var envelope: Dictionary = _load_snapshot(ITEMS_SNAPSHOT_FILE)
	if envelope.is_empty():
		return {"stackables": {}, "equipment": []}

	var data: Variant = envelope.get("data", {})
	return _normalize_items_payload(data)

func _normalize_stats_payload(raw_payload: Variant) -> Dictionary:
	if not (raw_payload is Dictionary):
		return {
			"rank": 1,
			"xp": 0,
			"next_rank_xp": 100,
			"current_nrg": 0,
			"max_nrg": 0,
			"nrg_regen_rate_seconds": 300,
			"seconds_until_next_nrg": 0.0,
			"last_entered_mission_id": "",
			"gil": 0,
			"lapis": 0,
			"username": ""
		}

	var payload: Dictionary = raw_payload
	return {
		"rank": int(payload.get("rank", 1)),
		"xp": int(payload.get("xp", 0)),
		"next_rank_xp": int(payload.get("next_rank_xp", 100)),
		"current_nrg": int(payload.get("current_nrg", 0)),
		"max_nrg": int(payload.get("max_nrg", 0)),
		"nrg_regen_rate_seconds": int(payload.get("nrg_regen_rate_seconds", 300)),
		"seconds_until_next_nrg": float(payload.get("seconds_until_next_nrg", 0.0)),
		"last_entered_mission_id": str(payload.get("last_entered_mission_id", "")),
		"gil": int(payload.get("gil", 0)),
		"lapis": int(payload.get("lapis", 0)),
		"username": str(payload.get("username", ""))
	}

func _load_stats_from_local() -> Dictionary:
	if _save_store == null:
		return {}

	var envelope: Dictionary = _load_snapshot(STATS_SNAPSHOT_FILE)
	if envelope.is_empty():
		return {}

	var data: Variant = envelope.get("data", {})
	if not (data is Dictionary):
		return {}

	return _normalize_stats_payload(data)

func _save_all_snapshots(source_event: String) -> void:
	_save_snapshot(STATS_SNAPSHOT_FILE, _snapshot_stats_payload(), source_event)
	_save_snapshot(ITEMS_SNAPSHOT_FILE, _snapshot_items_payload(), source_event)
	_save_snapshot(COMBAT_ITEMS_SNAPSHOT_FILE, _snapshot_combat_items_payload(), source_event)
	_save_snapshot(UNITS_SNAPSHOT_FILE, _snapshot_units_payload(), source_event)
	_save_snapshot(PARTIES_SNAPSHOT_FILE, _snapshot_parties_payload(), source_event)
	_save_snapshot(MISSION_PROGRESS_SNAPSHOT_FILE, _snapshot_mission_progress_payload(), source_event)

func set_combat_item(slot_index: int, item_id: String) -> void:
	if slot_index < 0 or slot_index >= COMBAT_ITEM_SLOT_COUNT:
		return

	var normalized_item_id: String = item_id.strip_edges()
	if normalized_item_id != "":
		if not game_data_items.has(normalized_item_id):
			normalized_item_id = ""
		else:
			var stackables: Dictionary = owned_items.get("stackables", {})
			if int(stackables.get(normalized_item_id, 0)) <= 0:
				normalized_item_id = ""

	if str(combat_items[slot_index]) == normalized_item_id:
		return

	combat_items[slot_index] = normalized_item_id
	combat_items_updated.emit(combat_items.duplicate())
	_save_combat_items_to_server()

func clear_all_combat_items() -> void:
	for i in range(COMBAT_ITEM_SLOT_COUNT):
		combat_items[i] = ""
	combat_items_updated.emit(combat_items.duplicate())
	_save_combat_items_to_server()

func _save_combat_items_to_server() -> void:
	_save_snapshot(COMBAT_ITEMS_SNAPSHOT_FILE, _snapshot_combat_items_payload(), "combat_items_saved")
	combat_items_saved.emit(combat_items.duplicate())

func update_account(new_username: String) -> bool:
	current_username = new_username
	_save_snapshot(STATS_SNAPSHOT_FILE, _snapshot_stats_payload(), "update_account")
	account_updated.emit(current_username)
	return true

func _derive_username_from_email(email: String) -> String:
	if email == "":
		return "Player"
	var at_index: int = email.find("@")
	if at_index <= 0:
		return email
	return email.substr(0, at_index)

func _load_initial_data(email: String) -> void:
	await _ensure_static_data_ready()

	var stats: Dictionary = _load_stats_from_local()
	
	# Apply stats with safe defaults
	current_rank = int(stats.get("rank", 1))
	current_xp = int(stats.get("xp", 0))
	next_rank_xp = int(stats.get("next_rank_xp", 100))
	current_nrg = int(stats.get("current_nrg", 0))
	max_nrg = int(stats.get("max_nrg", 0))
	nrg_regen_rate_seconds = int(stats.get("nrg_regen_rate_seconds", 300))
	seconds_until_next_nrg = float(stats.get("seconds_until_next_nrg", 0.0))
	last_entered_mission_id = str(stats.get("last_entered_mission_id", ""))
	gil = int(stats.get("gil", 0))
	lapis = int(stats.get("lapis", 0))
	current_username = str(stats.get("username", ""))
	if last_entered_mission_id != "":
		await _update_last_played_dungeon_from_mission(last_entered_mission_id)
	else:
		last_played_dungeon_name = ""

	await load_mission_progress()
	rank_updated.emit(current_rank, current_xp, next_rank_xp)
	nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
	currency_updated.emit(gil, lapis)

	owned_items = _load_items_from_local()
	items_updated.emit(owned_items)

	# === OFFLINE MIGRATION: Combat Items ===
	# FULLY MIGRATED: get_combat_items_async() — always uses local snapshot
	# Server communication disabled; combat items always loaded from local file
	combat_items = _load_combat_items_from_local()
	combat_items_loaded.emit(combat_items.duplicate())

	owned_units_ids = _load_units_from_local()
	units_updated.emit(owned_units_ids)
	
	var parties_payload: Dictionary = _load_parties_from_local()
	parties = parties_payload.get("parties", [])
	selected_party_index = _clamp_selected_party_index(int(parties_payload.get("selected_party_index", 0)))
	parties_updated.emit(parties)
	active_party_changed.emit(selected_party_index)
	
	account_info = null
	if current_username == "":
		current_username = _derive_username_from_email(email)
	account_updated.emit(current_username)

	_save_all_snapshots("initial_load")

	data_loaded.emit()

func _ensure_static_data_ready() -> void:
	if _static_data_loading:
		await _static_data_primed

	if not _static_data_ready:
		await _prime_static_data_cache()

	if _needs_static_data_refresh():
		await _refresh_static_data_cache()

func _prime_static_data_cache() -> void:
	if _static_data_ready or _static_data_loading:
		return

	_static_data_loading = true

	# Fast path: if sanitized cache matches on-disk versions, skip patcher entirely
	var early_sig: String = _build_static_data_signature()
	if early_sig != "" and _try_load_sanitized_cache(early_sig):
		_load_opcode_schemas()
		_static_data_ready = true
		_static_data_synced_with_server = false
		_static_data_loading = false
		_static_data_primed.emit()
		return

	var synced_with_server: bool = await _run_static_data_patch_cycle()
	_static_data_synced_with_server = synced_with_server

	_static_data_ready = true
	_static_data_loading = false
	_static_data_primed.emit()

func _refresh_static_data_cache() -> void:
	if _static_data_loading:
		await _static_data_primed
		return

	_static_data_loading = true
	var synced_with_server: bool = await _run_static_data_patch_cycle()
	_static_data_synced_with_server = synced_with_server
	_static_data_ready = true
	_static_data_loading = false
	_static_data_primed.emit()

func _run_background_static_data_sync() -> void:
	_static_data_sync_queued = false
	await _refresh_static_data_cache()

func _run_static_data_patch_cycle() -> bool:
	if not StaticDataLoader.patch_complete.is_connected(_on_patch_complete):
		StaticDataLoader.patch_progress.connect(func(file_name, status):
			pass
		)
		StaticDataLoader.patch_complete.connect(_on_patch_complete)

	StaticDataLoader.start_patching()
	await StaticDataLoader.patch_complete
	return false

func _needs_static_data_refresh() -> bool:
	if not StaticDataLoader or not StaticDataLoader.has_method("get_versions_snapshot"):
		return false

	var versions: Dictionary = StaticDataLoader.get_versions_snapshot()
	for file_type in StaticDataLoader.files_to_patch:
		if str(versions.get(file_type, "")).strip_edges() == "":
			return true
		if not FileAccess.file_exists("user://data/%s.json" % file_type):
			return true

	return false

func _sanitize_floats_to_ints(data: Variant) -> Variant:
	if typeof(data) == TYPE_DICTIONARY:
		var new_dict: Dictionary = {}
		for key in data:
			new_dict[key] = _sanitize_floats_to_ints(data[key])
		return new_dict
	elif typeof(data) == TYPE_ARRAY:
		var new_array: Array = []
		for item in data:
			new_array.append(_sanitize_floats_to_ints(item))
		return new_array
	elif typeof(data) == TYPE_FLOAT:
		if fmod(data, 1.0) == 0.0:
			return int(data)
	return data

func _on_patch_complete() -> void:
	var cache_signature: String = _build_static_data_signature()

	if _try_load_sanitized_cache(cache_signature):
		_load_opcode_schemas()
		return

	game_data_units = _sanitize_floats_to_ints(StaticDataLoader.get_data("units"))
	game_data_items = _sanitize_floats_to_ints(StaticDataLoader.get_data("items"))
	game_data_equipment = _sanitize_floats_to_ints(StaticDataLoader.get_data("equipment"))
	game_data_worlds = _sanitize_floats_to_ints(StaticDataLoader.get_data("worlds"))
	game_data_dungeons = _sanitize_floats_to_ints(StaticDataLoader.get_data("dungeons"))
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

	_save_sanitized_cache(cache_signature)
	_load_opcode_schemas()

func _build_static_data_signature() -> String:
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

	# Check signature file first — it's tiny, fast to read
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

	# Signature matches — load binary blob
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
		"summons_stat_patterns": game_data_summons_stat_patterns
	}

	# Write binary data blob
	var bin_path: String = "user://data/sanitized_data_cache.bin"
	var bin_file: FileAccess = FileAccess.open(bin_path, FileAccess.WRITE)
	if not bin_file:
		return
	bin_file.store_buffer(var_to_bytes(datasets))
	bin_file.close()

	# Write signature as separate tiny file
	var sig_path: String = "user://data/sanitized_cache_sig.txt"
	var sig_file: FileAccess = FileAccess.open(sig_path, FileAccess.WRITE)
	if sig_file:
		sig_file.store_string(signature)
		sig_file.close()

func _load_opcode_schemas() -> void:
	opcode_schemas_ready = false
	opcode_schema_error = ""
	opcode_skill_schema = _load_opcode_schema_file(OPCODE_SKILL_SCHEMA_PATH, "skill")
	opcode_passive_schema = _load_opcode_schema_file(OPCODE_PASSIVE_SCHEMA_PATH, "passive")

	if opcode_schema_error != "":
		return

	opcode_schemas_ready = true

func _load_opcode_schema_file(schema_path: String, schema_name: String) -> Dictionary:
	if not FileAccess.file_exists(schema_path):
		_record_opcode_schema_error("CRITICAL ERROR: Missing %s opcode schema at %s" % [schema_name, schema_path])
		return {}

	var json_as_text: String = FileAccess.get_file_as_string(schema_path)
	if json_as_text.strip_edges() == "":
		_record_opcode_schema_error("CRITICAL ERROR: Empty %s opcode schema at %s" % [schema_name, schema_path])
		return {}

	var parsed: Variant = JSON.parse_string(json_as_text)
	if parsed == null:
		_record_opcode_schema_error("CRITICAL ERROR: Invalid JSON in %s opcode schema at %s" % [schema_name, schema_path])
		return {}

	if not parsed is Dictionary:
		_record_opcode_schema_error("CRITICAL ERROR: %s opcode schema must parse as Dictionary at %s" % [schema_name, schema_path])
		return {}

	return parsed as Dictionary

func _record_opcode_schema_error(error_message: String) -> void:
	if opcode_schema_error == "":
		opcode_schema_error = error_message
	push_error(error_message)

func _ensure_opcode_schemas_ready(caller_name: String) -> bool:
	if opcode_schemas_ready:
		return true

	var details: String = opcode_schema_error if opcode_schema_error != "" else "CRITICAL ERROR: Opcode schemas not loaded."
	push_error("DataManager: %s cannot parse opcodes. %s" % [caller_name, details])
	return false

func parse_passive_effects(skill_data: Dictionary) -> Dictionary:
	if not _ensure_opcode_schemas_ready("parse_passive_effects"):
		return {"effects": []}

	return OpcodeParser.parse_passive(skill_data, opcode_passive_schema)

func parse_skill_effects(skill_data: Dictionary) -> Dictionary:
	if not _ensure_opcode_schemas_ready("parse_skill_effects"):
		return {
			"element_inflict": skill_data.get("element_inflict", []),
			"effects": []
		}

	return OpcodeParser.parse_skill(skill_data, opcode_skill_schema)

func _find_item_ability_id(effects_raw: Array) -> String:
	for effect in effects_raw:
		if effect.size() < 4:
			continue
		if int(effect[2]) != 71:
			continue

		var payload: Variant = effect[3]
		if typeof(payload) != TYPE_ARRAY or payload.size() == 0:
			continue

		return str(payload[0])

	return ""

func _get_active_skill_record(skill_id: String) -> Dictionary:
	var skill_data: Dictionary = game_data_skills_magic.get(skill_id, {})
	if not skill_data.is_empty():
		return skill_data

	return game_data_skills_ability.get(skill_id, {})

func _build_targeting_metadata(parsed_data: Dictionary) -> Dictionary:
	var metadata: Dictionary = {
		"needs_ally_selection": false,
		"targets_allies": false,
		"targets_enemies": false,
		"targets_self": false,
		"has_aoe": false
	}

	for effect in parsed_data.get("effects", []):
		var target_area: int = int(effect.get("target_area", 1))
		var target_type: int = int(effect.get("target_type", 1))

		if target_area == 2:
			metadata["has_aoe"] = true

		if target_type == 3:
			metadata["targets_self"] = true
		elif target_type == 1:
			metadata["targets_enemies"] = true
		elif target_type in [2, 6]:
			metadata["targets_allies"] = true
			if target_area == 1:
				metadata["needs_ally_selection"] = true

	return metadata

func resolve_combat_skill(skill_id: String) -> Dictionary:
	var resolved_skill: Dictionary = _get_active_skill_record(skill_id)
	if resolved_skill.is_empty():
		push_error("DataManager: Combat skill not found: %s" % skill_id)
		return {}

	var parsed_data: Dictionary = parse_skill_effects(resolved_skill)
	return {
		"source_type": "skill",
		"source_id": skill_id,
		"resolved_action_id": skill_id,
		"resolved_action_name": resolved_skill.get("name", ""),
		"resolved_action_data": resolved_skill,
		"parsed_data": parsed_data,
		"targeting": _build_targeting_metadata(parsed_data)
	}

func get_limitburst_max_gauge(limitburst_id: String) -> int:
	var default_max_gauge: int = 100
	if limitburst_id == "":
		return default_max_gauge

	var limitburst_data: Dictionary = game_data_limitbursts.get(limitburst_id, {})
	if limitburst_data.is_empty():
		push_error("DataManager: Limit burst data not found: %s" % limitburst_id)
		return default_max_gauge

	var levels: Variant = limitburst_data.get("levels", [])
	if not (levels is Array) or (levels as Array).is_empty():
		push_error("DataManager: Limit burst levels missing or invalid for id: %s" % limitburst_id)
		return default_max_gauge

	var first_level: Variant = (levels as Array)[0]
	if not (first_level is Array) or (first_level as Array).is_empty():
		push_error("DataManager: Limit burst first level invalid for id: %s" % limitburst_id)
		return default_max_gauge

	var gauge_value: Variant = (first_level as Array)[0]
	if typeof(gauge_value) not in [TYPE_INT, TYPE_FLOAT]:
		push_error("DataManager: Limit burst gauge value invalid for id: %s" % limitburst_id)
		return default_max_gauge

	return max(1, int(gauge_value))

func resolve_combat_limitburst(limitburst_id: String) -> Dictionary:
	var resolved_limitburst: Dictionary = game_data_limitbursts.get(limitburst_id, {})
	if resolved_limitburst.is_empty():
		push_error("DataManager: Combat limit burst not found: %s" % limitburst_id)
		return {}

	var parsed_data: Dictionary = parse_skill_effects(resolved_limitburst)
	return {
		"source_type": "limitburst",
		"source_id": limitburst_id,
		"resolved_action_id": limitburst_id,
		"resolved_action_name": resolved_limitburst.get("name", ""),
		"resolved_action_data": resolved_limitburst,
		"parsed_data": parsed_data,
		"targeting": _build_targeting_metadata(parsed_data)
	}

func resolve_combat_item(item_id: String) -> Dictionary:
	var item_data: Dictionary = game_data_items.get(item_id, {})
	if item_data.is_empty():
		push_error("DataManager: Combat item not found: %s" % item_id)
		return {}

	var resolved_ability_id: String = _find_item_ability_id(item_data.get("effects_raw", []))
	if resolved_ability_id == "":
		push_error("DataManager: Combat item missing opcode 71 ability reference: %s" % item_id)
		return {}

	var resolved_action_data: Dictionary = game_data_skills_ability.get(resolved_ability_id, {})
	if resolved_action_data.is_empty():
		push_error("DataManager: Combat item ability not found: %s -> %s" % [item_id, resolved_ability_id])
		return {}

	var parsed_data: Dictionary = parse_skill_effects(resolved_action_data)
	return {
		"source_type": "item",
		"source_id": item_id,
		"source_item_data": item_data,
		"resolved_action_id": resolved_ability_id,
		"resolved_action_name": resolved_action_data.get("name", item_data.get("name", "")),
		"resolved_action_data": resolved_action_data,
		"parsed_data": parsed_data,
		"targeting": _build_targeting_metadata(parsed_data),
		"original_item_id": item_id
	}

func _update_wallet_data(wallet: Dictionary) -> void:
	assert(wallet.has("gil"), "CRITICAL ERROR: wallet is missing gil!")
	if not wallet.has("gil"): push_error("CRITICAL ERROR: wallet is missing gil!")
	gil = int(wallet["gil"])
	if wallet.has("lapis"):
		lapis = int(wallet["lapis"])
	else:
		push_warning("wallet is missing lapis; keeping previous value")
	currency_updated.emit(gil, lapis)
	_save_snapshot(STATS_SNAPSHOT_FILE, _snapshot_stats_payload(), "wallet_update")

# === CLIENT-SIDE MUTATION HELPERS (Offline Mode) ===

func _generate_instance_id() -> String:
	var parts: Array = []
	var sizes: Array = [4, 2, 2, 2, 6]
	
	for size in sizes:
		var hex_part: String = ""
		for _i in range(size):
			hex_part += "%02x" % randi_range(0, 255)
		parts.append(hex_part)
	
	return "%s-%s-%s-%s-%s" % parts

func _get_item_cost(item_id: String) -> int:
	var item_data: Dictionary = game_data_items.get(item_id, {})
	if item_data.is_empty():
		item_data = game_data_equipment.get(item_id, {})
	return int(item_data.get("price_buy", 0))

func _apply_buy_item_local(item_id: String, quantity: int) -> bool:
	if not game_data_items.has(item_id) and not game_data_equipment.has(item_id):
		return false
	
	# Determine if this is equipment or stackable item
	var is_equipment: bool = game_data_equipment.has(item_id)
	var item_data: Dictionary = game_data_items.get(item_id, {})
	if item_data.is_empty():
		item_data = game_data_equipment.get(item_id, {})
	
	var cost_per_unit: int = _get_item_cost(item_id)
	var total_cost: int = cost_per_unit * quantity
	
	# Validate player has enough gil
	if gil < total_cost:
		return false
	
	# Deduct gil
	gil -= total_cost
	
	# Apply item acquisition based on type
	if is_equipment:
		# Generate new equipment instances
		if not owned_items.has("equipment"):
			owned_items["equipment"] = []
		for _i in range(quantity):
			var new_instance: Dictionary = {
				"instance_id": _generate_instance_id(),
				"template_id": item_id
			}
			(owned_items["equipment"] as Array).append(new_instance)
	else:
		# Stackable item
		if not owned_items.has("stackables"):
			owned_items["stackables"] = {}
		var current_qty: int = int(owned_items["stackables"].get(item_id, 0))
		owned_items["stackables"][item_id] = current_qty + quantity
	
	return true

func request_buy_item(item_id: String, quantity: int) -> void:
	if _apply_buy_item_local(item_id, quantity):
		items_updated.emit(owned_items)
		currency_updated.emit(gil, lapis)
		_save_snapshot(ITEMS_SNAPSHOT_FILE, _snapshot_items_payload(), "buy_item")
		_save_snapshot(STATS_SNAPSHOT_FILE, _snapshot_stats_payload(), "buy_item_currency")
		purchase_successful.emit()
	else:
		purchase_failed.emit("ERR_INSUFFICIENT_RESOURCES")

func request_start_mission(mission_id: String) -> Dictionary:
	var mission_data: Dictionary = await _get_or_load_mission_data(mission_id)
	if mission_data.is_empty():
		return {"success": false, "error": "Mission not found"}

	last_entered_mission_id = str(mission_id)
	await _update_last_played_dungeon_from_mission(mission_id)
	_save_snapshot(STATS_SNAPSHOT_FILE, _snapshot_stats_payload(), "start_mission")
	return {"success": true}

func load_mission_progress() -> void:
	var local_payload: Dictionary = _load_mission_progress_from_local()
	cleared_missions = local_payload.get("cleared_missions", {})
	latest_cleared_mission_id = str(local_payload.get("latest_cleared_mission_id", ""))

	if latest_cleared_mission_id != "":
		await _update_last_played_dungeon_from_mission(latest_cleared_mission_id)

	mission_progress_loaded.emit(latest_cleared_mission_id)

func get_latest_cleared_map_selection() -> Dictionary:
	if latest_cleared_mission_id == "":
		return {}
	return await get_map_selection_for_mission(latest_cleared_mission_id)

func get_map_selection_for_mission(mission_id: String) -> Dictionary:
	var mission_data: Dictionary = await _get_or_load_mission_data(mission_id)
	if mission_data.is_empty():
		return {}

	var dungeon_id: String = str(int(mission_data.get("dungeon_id", "")))
	if dungeon_id == "":
		return {}

	var map_location: Dictionary = _find_dungeon_location_in_worlds(dungeon_id)
	if map_location.is_empty():
		return {}

	map_location["mission_id"] = mission_id
	map_location["dungeon_id"] = dungeon_id
	return map_location

func _update_last_played_dungeon_from_mission(mission_id: String) -> void:
	if mission_id == "":
		last_played_dungeon_name = ""
		return

	var mission_data: Dictionary = await _get_or_load_mission_data(mission_id)

	if mission_data.is_empty():
		return

	var dungeon_id: String = str(int(mission_data.get("dungeon_id", "")))
	if dungeon_id == "":
		return

	var dungeon_data: Dictionary = game_data_dungeons.get(dungeon_id, {})
	if dungeon_data.is_empty():
		return

	if dungeon_data.has("names") and dungeon_data["names"] is Array and dungeon_data["names"].size() > 0:
		var dungeon_name: String = str(dungeon_data["names"][0])
		last_played_dungeon_name = dungeon_name.replace(" ", "_")

func _get_or_load_mission_data_local(mission_id: String) -> Dictionary:
	var mission_key: String = str(mission_id)
	if game_data_missions.is_empty() and FileAccess.file_exists("user://data/missions.json"):
		var mission_text: String = FileAccess.get_file_as_string("user://data/missions.json")
		var parsed_missions: Variant = JSON.parse_string(mission_text)
		if parsed_missions is Dictionary:
			game_data_missions = _sanitize_floats_to_ints(parsed_missions)

	var mission_data: Dictionary = game_data_missions.get(mission_key, {})
	mission_data = _normalize_mission_data(mission_data)
	if not mission_data.is_empty():
		game_data_missions[mission_key] = mission_data

	return mission_data

func get_mission_data_local(mission_id: String) -> Dictionary:
	return _get_or_load_mission_data_local(mission_id)

func _get_or_load_mission_data(mission_id: String) -> Dictionary:
	var mission_key: String = str(mission_id)
	var mission_data: Dictionary = _get_or_load_mission_data_local(mission_key)

	return mission_data

func _normalize_mission_data(mission_data: Dictionary) -> Dictionary:
	if mission_data.is_empty():
		return mission_data

	if mission_data.has("challenges"):
		var raw_challenges: Variant = mission_data.get("challenges")
		if raw_challenges is Dictionary and raw_challenges.is_empty():
			mission_data["challenges"] = []
		elif raw_challenges == null:
			mission_data["challenges"] = []

	return mission_data

func _get_latest_cleared_mission_id_from_progress(progress: Dictionary) -> String:
	var latest_numeric_id: int = -1

	for mission_key in progress.keys():
		var mission_key_str: String = str(mission_key)
		var progress_entry: Variant = progress[mission_key]
		if progress_entry is Dictionary and progress_entry.has("cleared") and progress_entry["cleared"] == false:
			continue

		var numeric_id: int = _extract_mission_numeric_id(mission_key_str)
		if numeric_id > latest_numeric_id:
			latest_numeric_id = numeric_id

	if latest_numeric_id < 0:
		return ""

	return str(latest_numeric_id)

func _extract_mission_numeric_id(mission_key: String) -> int:
	var numeric_str: String = mission_key
	if numeric_str.begins_with("mission_"):
		numeric_str = numeric_str.substr(8)

	if not numeric_str.is_valid_int():
		return -1

	return int(numeric_str)

func _find_dungeon_location_in_worlds(dungeon_id: String) -> Dictionary:
	for world_id in game_data_worlds.keys():
		var world_data: Dictionary = game_data_worlds.get(world_id, {})
		var regions: Dictionary = world_data.get("regions", {})
		for region_id in regions.keys():
			var region_data: Dictionary = regions.get(region_id, {})
			var subregions: Dictionary = region_data.get("subregions", {})
			for subregion_id in subregions.keys():
				var subregion_data: Dictionary = subregions.get(subregion_id, {})
				var dungeons: Variant = subregion_data.get("dungeons", [])
				if _subregion_contains_dungeon(dungeons, dungeon_id):
					return {
						"world_id": str(world_id),
						"region_id": str(region_id),
						"subregion_id": str(subregion_id)
					}

	return {}

func _subregion_contains_dungeon(dungeons: Variant, dungeon_id: String) -> bool:
	if dungeons is Dictionary:
		for candidate_id in dungeons.keys():
			if str(candidate_id) == dungeon_id:
				return true
		return false

	if dungeons is Array:
		for candidate_id in dungeons:
			if str(candidate_id) == dungeon_id:
				return true
		return false

	if dungeons is String:
		return str(dungeons) == dungeon_id

	return false

func _clamp_selected_party_index(candidate_index: int) -> int:
	if parties.is_empty():
		return 0
	return clampi(candidate_index, 0, parties.size() - 1)

func get_selected_party_index() -> int:
	return _clamp_selected_party_index(selected_party_index)

func set_selected_party_index(new_index: int) -> bool:
	var next_index: int = _clamp_selected_party_index(new_index)
	if selected_party_index == next_index:
		return false

	selected_party_index = next_index
	active_party_changed.emit(selected_party_index)
	return true

func get_active_party() -> Dictionary:
	if parties.is_empty():
		return {}

	var index: int = _clamp_selected_party_index(selected_party_index)
	if index < 0 or index >= parties.size():
		return {}

	var party_entry: Variant = parties[index]
	if party_entry is Dictionary:
		return party_entry
	return {}

func save_parties(new_parties: Array) -> Dictionary:
	var selected_for_save: int = 0
	if not new_parties.is_empty():
		selected_for_save = clampi(selected_party_index, 0, new_parties.size() - 1)

	var previous_selected_local: int = selected_party_index
	parties = new_parties
	selected_party_index = _clamp_selected_party_index(selected_for_save)
	parties_updated.emit(parties)
	_save_snapshot(PARTIES_SNAPSHOT_FILE, _snapshot_parties_payload(), "parties_saved")
	if selected_party_index != previous_selected_local:
		active_party_changed.emit(selected_party_index)
	return {
		"success": true,
		"parties": parties,
		"selected_party_index": selected_party_index
	}

func assign_unit_to_party(party_index: int, slot_index: int, instance_id: String) -> void:
	if party_index >= 0 and party_index < parties.size():
		var new_parties: Array = parties.duplicate(true)
		new_parties[party_index]["units"][slot_index] = instance_id
		party_save_requested.emit(new_parties)

func summon_units(amount: int) -> Dictionary:
	var summoned_units: Array = []
	var unit_ids: Array = []
	for unit_id in game_data_units.keys():
		var unit_data: Variant = game_data_units.get(str(unit_id), {})
		if _is_standard_summonable_unit(unit_data):
			unit_ids.append(str(unit_id))

	if unit_ids.is_empty():
		return {"error": "ERR_NO_UNITS_AVAILABLE"}

	for _i in range(amount):
		var random_unit_id: String = unit_ids[randi() % unit_ids.size()]
		var initial_rarity: int = _get_unit_initial_rarity(random_unit_id)
		var new_instance: Dictionary = {
			"unit_id": random_unit_id,
			"instance_id": _generate_instance_id(),
			"xp": 0,
			"level": 1,
			"next_xp": 1000,
			"equipment": {},
			"is_locked": false,
			"trust_value": 0,
			"trust_reward_claimed": false,
			"limitburst_xp": 0,
			"limitburst_level": 1,
			"current_rarity": initial_rarity,
			"current_accumulated_exp": 0
		}
		summoned_units.append(new_instance)

	summoned_units = _hydrate_owned_units(summoned_units)
	owned_units_ids.append_array(summoned_units)
	units_updated.emit(owned_units_ids)
	_save_snapshot(UNITS_SNAPSHOT_FILE, _snapshot_units_payload(), "summon_units")
	return {"summoned": summoned_units}

func _is_standard_summonable_unit(unit_data: Variant) -> bool:
	if not (unit_data is Dictionary):
		return false

	var data: Dictionary = unit_data
	if data.get("is_summonable", false) != true:
		return false

	var rarity_min: int = int(data.get("rarity_min", 0))
	return rarity_min < 7

func summon_exp_boost_units(amount: int = 3) -> Dictionary:
	return _summon_fixed_units_local("900020401", amount, "summon_exp_boost_units")

func summon_trust_units(amount: int = 3) -> Dictionary:
	return _summon_fixed_units_local("904000105", amount, "summon_trust_units")

func _summon_fixed_units_local(unit_id: String, amount: int, source_event: String) -> Dictionary:
	var unit_data: Dictionary = game_data_units.get(unit_id, {})
	if unit_data.is_empty():
		return {"error": "Unit data not found for unit_id %s" % unit_id}

	var summon_amount: int = maxi(1, amount)
	var summoned_units: Array = []
	var initial_rarity: int = _get_unit_initial_rarity(unit_id)

	for _i in range(summon_amount):
		var new_instance: Dictionary = {
			"unit_id": unit_id,
			"instance_id": _generate_instance_id(),
			"xp": 0,
			"level": 1,
			"next_xp": 1000,
			"equipment": {},
			"is_locked": false,
			"trust_value": 0,
			"trust_reward_claimed": false,
			"limitburst_xp": 0,
			"limitburst_level": 1,
			"current_rarity": initial_rarity,
			"current_accumulated_exp": 0
		}
		summoned_units.append(new_instance)

	summoned_units = _hydrate_owned_units(summoned_units)
	owned_units_ids.append_array(summoned_units)
	units_updated.emit(owned_units_ids)
	_save_snapshot(UNITS_SNAPSHOT_FILE, _snapshot_units_payload(), source_event)
	return {"summoned": summoned_units}

func _handle_summoned_units(result: Dictionary) -> Dictionary:
	if result.has("error"):
		return result
	var summoned_units: Array = result.get("summoned", [])
	summoned_units = _hydrate_owned_units(summoned_units)
	owned_units_ids.append_array(summoned_units)
	units_updated.emit(owned_units_ids)
	_save_snapshot(UNITS_SNAPSHOT_FILE, _snapshot_units_payload(), "summon_units")
	return {"summoned": summoned_units}

func _get_unit_initial_rarity(unit_id: String) -> int:
	var unit_data: Dictionary = game_data_units.get(unit_id, {})
	var rarity_min: int = int(unit_data.get("rarity_min", 0))
	if rarity_min > 0:
		return rarity_min

	var entries: Variant = unit_data.get("entries", {})
	if entries is Dictionary:
		var min_rarity: int = 99
		for key in entries.keys():
			var entry: Variant = entries[key]
			if entry is Dictionary and entry.has("rarity"):
				var r: int = int(entry.get("rarity", 0))
				if r > 0 and r < min_rarity:
					min_rarity = r
		if min_rarity != 99:
			return min_rarity

	return 1

func _get_unit_type(unit_data: Dictionary) -> String:
	if unit_data.is_empty():
		return UNIT_TYPE_PLAYABLE
	if int(unit_data.get("job_id", 0)) == EXP_UNIT_JOB_ID:
		return UNIT_TYPE_EXP_MATERIAL
	if int(unit_data.get("job_id", 0)) == TRUST_MATERIAL_JOB_ID:
		return UNIT_TYPE_TRUST_MATERIAL
	return UNIT_TYPE_PLAYABLE

func _get_raw_unit_exp_pattern(unit_id: String, unit_data: Dictionary, rarity: int = -1) -> int:
	var entries: Variant = unit_data.get("entries", {})
	if entries is Dictionary:
		if rarity >= 0:
			for entry_key in entries.keys():
				var entry: Variant = entries[entry_key]
				if entry is Dictionary and int(entry.get("rarity", -1)) == rarity:
					if entry.has("exp_pattern"):
						return int(entry.get("exp_pattern", 0))

		if entries.has(unit_id):
			var keyed_entry: Variant = entries[unit_id]
			if keyed_entry is Dictionary and keyed_entry.has("exp_pattern"):
				return int(keyed_entry.get("exp_pattern", 0))

		for entry_key in entries.keys():
			var fallback_entry: Variant = entries[entry_key]
			if fallback_entry is Dictionary and fallback_entry.has("exp_pattern"):
				return int(fallback_entry.get("exp_pattern", 0))

	return 0

func _get_exp_unit_yield(unit_id: String, unit_data: Dictionary) -> int:
	if int(unit_data.get("job_id", 0)) != EXP_UNIT_JOB_ID:
		return 0
	var exp_pattern: int = _get_raw_unit_exp_pattern(unit_id, unit_data, int(unit_data.get("rarity_min", 1)))
	return int(EXP_UNIT_YIELD_BY_PATTERN.get(exp_pattern, 0))

func _get_base_exp_yield(unit: Dictionary, unit_data: Dictionary) -> int:
	if unit_data.has("base_exp_yield"):
		return int(unit_data.get("base_exp_yield", 0))

	var unit_type: String = _get_unit_type(unit_data)
	if unit_type == UNIT_TYPE_EXP_MATERIAL:
		return _get_exp_unit_yield(str(unit.get("unit_id", "")), unit_data)

	if unit_type == UNIT_TYPE_PLAYABLE:
		var rarity: int = maxi(1, int(unit.get("current_rarity", int(unit_data.get("rarity_min", 1)))))
		return ENHANCE_BASE_XP_GAIN + (rarity * ENHANCE_XP_PER_RARITY) + ENHANCE_XP_PER_LEVEL

	return 0

func _get_material_accumulated_exp(material_unit: Dictionary) -> int:
	if material_unit.has("current_accumulated_exp"):
		return maxi(0, int(material_unit.get("current_accumulated_exp", 0)))
	if material_unit.has("bonus_exp"):
		return maxi(0, int(material_unit.get("bonus_exp", 0)))
	return maxi(0, int(material_unit.get("xp", 0)))

func _get_material_accumulated_trust(material_unit: Dictionary) -> float:
	return max(0.0, float(material_unit.get("trust_value", 0.0)))

func _get_trust_yield(unit_id: String, unit_data: Dictionary) -> float:
	if unit_data.has("trust_yield"):
		return max(0.0, float(unit_data.get("trust_yield", 0.0)))
	return float(TRUST_YIELD_BY_UNIT_ID.get(int(unit_id), 0.0))

func _get_trust_mastery_id(unit_data: Dictionary) -> String:
	if unit_data.has("trust_mastery_id") and str(unit_data.get("trust_mastery_id", "")) != "":
		return str(unit_data.get("trust_mastery_id", ""))
	var tmr_value: Variant = unit_data.get("TMR", null)
	if tmr_value is Array and tmr_value.size() >= 2 and tmr_value[1] != null:
		return str(tmr_value[1])
	return ""

func _is_duplicate_unit(base_unit: Dictionary, base_unit_data: Dictionary, material_unit: Dictionary, material_unit_data: Dictionary) -> bool:
	if str(base_unit.get("unit_id", "")) == str(material_unit.get("unit_id", "")):
		return true
	var base_mastery: String = _get_trust_mastery_id(base_unit_data)
	var material_mastery: String = _get_trust_mastery_id(material_unit_data)
	return base_mastery != "" and material_mastery != "" and base_mastery == material_mastery

func _get_max_accumulated_exp(unit_data: Dictionary) -> int:
	if unit_data.has("max_accumulated_exp"):
		return maxi(0, int(unit_data.get("max_accumulated_exp", DEFAULT_MAX_ACCUMULATED_EXP)))
	return DEFAULT_MAX_ACCUMULATED_EXP

func _resolve_trust_reward(unit_data: Dictionary) -> Dictionary:
	if unit_data.is_empty():
		return {"error": "Missing unit static data for trust reward"}

	var tmr_value: Variant = unit_data.get("TMR", null)
	if tmr_value is Array and tmr_value.size() >= 2 and tmr_value[1] != null:
		var reward_type: String = str(tmr_value[0])
		var reward_id: String = str(tmr_value[1])
		if reward_type == "EQUIP":
			if not game_data_equipment.has(reward_id):
				return {"error": "Trust reward equipment template not found"}
			return {"reward_type": "EQUIP", "template_id": reward_id}
		elif reward_type == "MATERIA":
			if not game_data_materia.has(reward_id):
				return {"error": "Trust reward materia template not found"}
			return {"reward_type": "MATERIA", "template_id": reward_id}
		else:
			return {"error": "Unsupported trust reward type: %s" % reward_type}

	var trust_mastery_id: String = str(unit_data.get("trust_mastery_id", ""))
	if trust_mastery_id != "":
		if game_data_equipment.has(trust_mastery_id):
			return {"reward_type": "EQUIP", "template_id": trust_mastery_id}
		if game_data_materia.has(trust_mastery_id):
			return {"reward_type": "MATERIA", "template_id": trust_mastery_id}

	return {"error": "No supported trust reward configured"}

func _grant_instanced_item_local(item_type: String, template_id: String, amount: int) -> Dictionary:
	var grant_count: int = maxi(1, amount)
	var granted_items: Array = []
	if not owned_items.has("equipment") or not (owned_items.get("equipment", []) is Array):
		owned_items["equipment"] = []

	for _i in range(grant_count):
		var item_instance: Dictionary = {
			"instance_id": _generate_instance_id(),
			"template_id": str(template_id),
			"item_type": str(item_type),
			"equipped_to": ""
		}
		granted_items.append(item_instance)
		(owned_items["equipment"] as Array).append(item_instance)

	return {
		"success": true,
		"granted_items": granted_items
	}

func _calculate_material_enhance_gains(material_unit: Dictionary, material_unit_data: Dictionary) -> Dictionary:
	var material_type: String = _get_unit_type(material_unit_data)

	if material_type == UNIT_TYPE_EXP_MATERIAL:
		var exp_total: int = _get_base_exp_yield(material_unit, material_unit_data) + _get_material_accumulated_exp(material_unit)
		return {"xp_gain": exp_total, "trust_gain": 0.0, "limitburst_gain": 0}

	if material_type == UNIT_TYPE_TRUST_MATERIAL:
		var trust_total: float = _get_trust_yield(str(material_unit.get("unit_id", "")), material_unit_data) + _get_material_accumulated_trust(material_unit)
		return {"xp_gain": 0, "trust_gain": trust_total, "limitburst_gain": 0}

	var base_exp: int = _get_base_exp_yield(material_unit, material_unit_data)
	var stored_exp: int = _get_material_accumulated_exp(material_unit)
	var xp_gain: int = base_exp + int(floor(float(stored_exp) * PLAYABLE_ACCUMULATED_EXP_TRANSFER_RATE))
	return {"xp_gain": xp_gain, "trust_gain": 0.0, "limitburst_gain": 0}

func _is_unit_assigned_to_any_party(unit_instance_id: String) -> bool:
	for party_entry in parties:
		if not (party_entry is Dictionary):
			continue
		var units_value: Variant = party_entry.get("units", [])
		if units_value is Array:
			for assigned_instance_id in units_value:
				if str(assigned_instance_id) == unit_instance_id:
					return true
	return false

func _get_unit_max_level_local(unit: Dictionary) -> int:
	var rarity: int = int(unit.get("current_rarity", 1))
	return int(StatCalculator.RARITY_MAX_LEVELS.get(rarity, 15))

func _ensure_unit_exp_patterns_loaded() -> void:
	if not _unit_exp_patterns_cache.is_empty():
		return

	var file_path: String = "res://assets/static_data/unit-exp-pattern.csv"
	if not FileAccess.file_exists(file_path):
		return

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return

	var header_line: String = file.get_line().strip_edges()
	var headers: PackedStringArray = header_line.split(",")
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line == "":
			continue
		var cols: PackedStringArray = line.split(",")
		if cols.size() < 2:
			continue
		var level: int = int(cols[0])
		for i in range(1, mini(headers.size(), cols.size())):
			var header: String = headers[i].strip_edges()
			var pattern_value_str: String = header.replace("Gr ", "")
			var pattern: int = int(pattern_value_str)
			if pattern <= 0:
				continue
			if not _unit_exp_patterns_cache.has(pattern):
				_unit_exp_patterns_cache[pattern] = {}
			var value_text: String = cols[i].strip_edges()
			var value: int = 0
			if value_text != "-" and value_text != "":
				value = int(value_text)
			_unit_exp_patterns_cache[pattern][level] = value

func _calculate_xp_for_level_local(level: int, exp_pattern: int) -> int:
	_ensure_unit_exp_patterns_loaded()
	if not _unit_exp_patterns_cache.has(exp_pattern):
		return 0
	var table: Dictionary = _unit_exp_patterns_cache[exp_pattern]
	return int(table.get(level, 0))

func _calculate_total_xp_for_level_local(level: int, exp_pattern: int) -> int:
	var total: int = 0
	for l in range(2, level + 1):
		total += _calculate_xp_for_level_local(l, exp_pattern)
	return total

func _calculate_level_from_xp_local(total_xp: int, exp_pattern: int, max_level: int) -> int:
	var level: int = 1
	var remaining: int = maxi(0, total_xp)
	while level < max_level:
		var required: int = _calculate_xp_for_level_local(level + 1, exp_pattern)
		if required <= 0 or remaining < required:
			break
		remaining -= required
		level += 1
	return level

func _update_unit_next_xp_local(unit: Dictionary, unit_data: Dictionary) -> void:
	var exp_pattern: int = _get_raw_unit_exp_pattern(str(unit.get("unit_id", "")), unit_data, int(unit.get("current_rarity", 1)))
	if exp_pattern <= 0:
		exp_pattern = 5

	var max_level: int = _get_unit_max_level_local(unit)
	var level: int = int(unit.get("level", 1))
	if level < max_level:
		var base_xp: int = _calculate_total_xp_for_level_local(level, exp_pattern)
		var xp_into_level: int = int(unit.get("xp", 0)) - base_xp
		var required_marginal_xp: int = _calculate_xp_for_level_local(level + 1, exp_pattern)
		unit["next_xp"] = maxi(0, required_marginal_xp - xp_into_level)
	else:
		unit["next_xp"] = 0

func add_unit_xp(instance_id: String, xp_amount: int) -> Dictionary:
	var unit_found: bool = false
	for unit in owned_units_ids:
		if unit is Dictionary and unit.get("instance_id", "") == instance_id:
			unit["xp"] = int(unit.get("xp", 0)) + xp_amount
			unit_found = true
			break

	if unit_found:
		owned_units_ids = _hydrate_owned_units(owned_units_ids)
		units_updated.emit(owned_units_ids)
		_save_snapshot(UNITS_SNAPSHOT_FILE, _snapshot_units_payload(), "add_unit_xp")
		return {"success": true}
	else:
		return {"error": "ERR_UNIT_NOT_FOUND"}

func awaken_unit(instance_id: String) -> Dictionary:
	var unit_found: bool = false
	for unit in owned_units_ids:
		if unit is Dictionary and unit.get("instance_id", "") == instance_id:
			var current_rarity: int = int(unit.get("current_rarity", 1))
			if current_rarity < 7:
				unit["current_rarity"] = current_rarity + 1
				unit_found = true
			break

	if unit_found:
		owned_units_ids = _hydrate_owned_units(owned_units_ids)
		units_updated.emit(owned_units_ids)
		_save_snapshot(UNITS_SNAPSHOT_FILE, _snapshot_units_payload(), "awaken_unit")
		return {"success": true}
	else:
		return {"error": "ERR_UNIT_NOT_FOUND"}
	
func enhance_unit(base_unit_instance_id: String, material_unit_instance_ids: Array) -> Dictionary:
	# === CLIENT-SIDE LOCAL-ONLY MODE ===
	if base_unit_instance_id == "":
		return {"success": false, "error": "Invalid base_unit_instance_id"}
	if material_unit_instance_ids.is_empty():
		return {"success": false, "error": "material_unit_instance_ids must be a non-empty array"}

	var seen_materials: Dictionary = {}
	for material_id_value in material_unit_instance_ids:
		var material_id: String = str(material_id_value)
		if material_id == "":
			return {"success": false, "error": "All material ids must be non-empty strings"}
		if seen_materials.has(material_id):
			return {"success": false, "error": "Duplicate material ids are not allowed"}
		seen_materials[material_id] = true
		if material_id == base_unit_instance_id:
			return {"success": false, "error": "Base unit cannot be used as enhancement material"}

	var base_unit: Dictionary = {}
	var base_index: int = -1
	for i in range(owned_units_ids.size()):
		var candidate: Variant = owned_units_ids[i]
		if candidate is Dictionary and str(candidate.get("instance_id", "")) == base_unit_instance_id:
			base_unit = candidate
			base_index = i
			break
	if base_index < 0:
		return {"success": false, "error": "Ownership check failed for base unit"}

	var base_unit_data: Dictionary = game_data_units.get(str(base_unit.get("unit_id", "")), {})
	if base_unit_data.is_empty():
		return {"success": false, "error": "Base unit data not found"}

	var base_max_level: int = _get_unit_max_level_local(base_unit)
	var base_unit_type: String = _get_unit_type(base_unit_data)
	if base_unit_type == UNIT_TYPE_PLAYABLE:
		if int(base_unit.get("level", 1)) >= base_max_level and float(base_unit.get("trust_value", 0.0)) >= ENHANCE_MAX_TRUST_VALUE:
			return {"success": false, "error": "Base unit is already at maximum level and trust"}

	var material_units: Array = []
	for material_id_value in material_unit_instance_ids:
		var material_id: String = str(material_id_value)
		var material_unit: Dictionary = {}
		var found_material: bool = false
		for unit_value in owned_units_ids:
			if unit_value is Dictionary and str(unit_value.get("instance_id", "")) == material_id:
				material_unit = unit_value
				found_material = true
				break
		if not found_material:
			return {"success": false, "error": "Ownership check failed for one or more material units"}

		if bool(material_unit.get("is_locked", false)):
			return {"success": false, "error": "One or more material units are locked"}

		if _is_unit_assigned_to_any_party(material_id):
			return {"success": false, "error": "One or more material units are assigned to a party"}

		var material_unit_data: Dictionary = game_data_units.get(str(material_unit.get("unit_id", "")), {})
		if material_unit_data.is_empty():
			return {"success": false, "error": "Material unit data not found"}

		var material_type: String = _get_unit_type(material_unit_data)
		if material_type == UNIT_TYPE_PLAYABLE and float(material_unit.get("trust_value", 0.0)) >= ENHANCE_MAX_TRUST_VALUE:
			return {"success": false, "error": "One or more material units are already at 100% trust"}

		if base_unit_type == UNIT_TYPE_EXP_MATERIAL and material_type != UNIT_TYPE_EXP_MATERIAL:
			return {"success": false, "error": "Cannot use non-EXP materials to enhance an EXP unit"}

		if base_unit_type == UNIT_TYPE_TRUST_MATERIAL and material_type != UNIT_TYPE_TRUST_MATERIAL:
			return {"success": false, "error": "Cannot use non-trust materials to enhance a trust material unit"}

		material_units.append(material_unit)

	var total_cost: int = material_unit_instance_ids.size() * ENHANCE_GIL_COST_PER_MATERIAL
	if gil < total_cost:
		return {"success": false, "error": "Insufficient gil"}
	gil -= total_cost

	var granted_trust_reward: Variant = {}
	var trust_reward_warning: String = ""

	if base_unit_type == UNIT_TYPE_EXP_MATERIAL:
		var total_exp_to_add: int = 0
		for material_unit_value in material_units:
			var material_unit: Dictionary = material_unit_value
			var material_unit_data: Dictionary = game_data_units.get(str(material_unit.get("unit_id", "")), {})
			var gains: Dictionary = _calculate_material_enhance_gains(material_unit, material_unit_data)
			total_exp_to_add += int(gains.get("xp_gain", 0))

		var max_accumulated_exp: int = _get_max_accumulated_exp(base_unit_data)
		base_unit["current_accumulated_exp"] = mini(max_accumulated_exp, int(base_unit.get("current_accumulated_exp", 0)) + total_exp_to_add)
	elif base_unit_type == UNIT_TYPE_TRUST_MATERIAL:
		var total_trust_to_add: float = 0.0
		for material_unit_value in material_units:
			var material_unit: Dictionary = material_unit_value
			var material_unit_data: Dictionary = game_data_units.get(str(material_unit.get("unit_id", "")), {})
			var gains: Dictionary = _calculate_material_enhance_gains(material_unit, material_unit_data)
			total_trust_to_add += float(gains.get("trust_gain", 0.0))

		base_unit["trust_value"] = min(ENHANCE_MAX_TRUST_VALUE, float(base_unit.get("trust_value", 0.0)) + total_trust_to_add)
	else:
		var total_xp_gain: int = 0
		var total_trust_gain: float = 0.0
		var previous_trust_value: float = float(base_unit.get("trust_value", 0.0))

		for material_unit_value in material_units:
			var material_unit: Dictionary = material_unit_value
			var material_unit_data: Dictionary = game_data_units.get(str(material_unit.get("unit_id", "")), {})
			var gains: Dictionary = _calculate_material_enhance_gains(material_unit, material_unit_data)
			total_xp_gain += int(gains.get("xp_gain", 0))
			total_trust_gain += float(gains.get("trust_gain", 0.0))

			if _get_unit_type(material_unit_data) == UNIT_TYPE_PLAYABLE and _is_duplicate_unit(base_unit, base_unit_data, material_unit, material_unit_data):
				total_trust_gain += PLAYABLE_DUPLICATE_TRUST_BONUS + _get_material_accumulated_trust(material_unit)

		base_unit["xp"] = int(base_unit.get("xp", 0)) + total_xp_gain
		var exp_pattern: int = _get_raw_unit_exp_pattern(str(base_unit.get("unit_id", "")), base_unit_data, int(base_unit.get("current_rarity", 1)))
		if exp_pattern <= 0:
			exp_pattern = 5
		base_unit["level"] = _calculate_level_from_xp_local(int(base_unit.get("xp", 0)), exp_pattern, base_max_level)
		_update_unit_next_xp_local(base_unit, base_unit_data)

		base_unit["trust_value"] = min(ENHANCE_MAX_TRUST_VALUE, float(base_unit.get("trust_value", 0.0)) + total_trust_gain)

		if previous_trust_value < ENHANCE_MAX_TRUST_VALUE and float(base_unit.get("trust_value", 0.0)) >= ENHANCE_MAX_TRUST_VALUE and not bool(base_unit.get("trust_reward_claimed", false)):
			var reward_info: Dictionary = _resolve_trust_reward(base_unit_data)
			if reward_info.has("template_id"):
				var reward_type: String = str(reward_info.get("reward_type", ""))
				var reward_template_id: String = str(reward_info.get("template_id", ""))
				var grant_result: Dictionary = _grant_instanced_item_local(reward_type, reward_template_id, 1)
				if bool(grant_result.get("success", false)):
					var granted_items: Array = grant_result.get("granted_items", [])
					granted_trust_reward = {
						"reward_type": reward_type,
						"template_id": reward_template_id,
						"quantity": 1,
						"granted_equipment": granted_items
					}
					base_unit["trust_reward_claimed"] = true
				else:
					trust_reward_warning = "Failed to grant trust reward"
			else:
				trust_reward_warning = str(reward_info.get("error", "No supported trust reward configured"))

	owned_units_ids[base_index] = base_unit
	var material_id_set: Dictionary = {}
	for material_id_value in material_unit_instance_ids:
		material_id_set[str(material_id_value)] = true

	var filtered_units: Array = []
	for unit_value in owned_units_ids:
		if unit_value is Dictionary:
			var instance_id: String = str(unit_value.get("instance_id", ""))
			if material_id_set.has(instance_id):
				continue
		filtered_units.append(unit_value)

	owned_units_ids = _hydrate_owned_units(filtered_units)
	units_updated.emit(owned_units_ids)
	currency_updated.emit(gil, lapis)
	_save_snapshot(UNITS_SNAPSHOT_FILE, _snapshot_units_payload(), "enhance_unit")
	_save_snapshot(STATS_SNAPSHOT_FILE, _snapshot_stats_payload(), "enhance_unit")

	if granted_trust_reward != null:
		items_updated.emit(owned_items)
		_save_snapshot(ITEMS_SNAPSHOT_FILE, _snapshot_items_payload(), "enhance_unit")

	var updated_base_unit: Dictionary = {}
	for unit_value in owned_units_ids:
		if unit_value is Dictionary and str(unit_value.get("instance_id", "")) == base_unit_instance_id:
			updated_base_unit = unit_value
			break

	var response: Dictionary = {
		"success": true,
		"updated_base_unit": {
			"instance_id": str(updated_base_unit.get("instance_id", base_unit_instance_id)),
			"level": int(updated_base_unit.get("level", base_unit.get("level", 1))),
			"xp": int(updated_base_unit.get("xp", base_unit.get("xp", 0))),
			"trust_value": float(updated_base_unit.get("trust_value", base_unit.get("trust_value", 0.0))),
			"limitburst_level": int(updated_base_unit.get("limitburst_level", base_unit.get("limitburst_level", 1))),
			"limitburst_xp": int(updated_base_unit.get("limitburst_xp", base_unit.get("limitburst_xp", 0))),
			"current_accumulated_exp": int(updated_base_unit.get("current_accumulated_exp", base_unit.get("current_accumulated_exp", 0)))
		},
		"consumed_material_ids": material_unit_instance_ids.duplicate(),
		"updated_currency": {
			"gil": gil
		},
		"granted_trust_reward": granted_trust_reward,
		"trust_reward_warning": trust_reward_warning,
		# Backward-compatible field consumed by current enhance_ui.gd
		"enhanced_unit": updated_base_unit
	}
	return response
	
func request_equip_item(instance_id: String, slot_id: String, item_id: String) -> void:
	if item_id != "" and not _equipment_exists(item_id):
		equip_failed.emit("ERR_EQUIPMENT_NOT_FOUND")
		return

	if item_id != "":
		var item_data_dict: Dictionary = {}
		if owned_items.has("equipment"):
			for item in owned_items["equipment"]:
				if item is Dictionary and item.get("instance_id") == item_id:
					var template_id: String = item.get("template_id", "")
					if game_data_equipment.has(template_id):
						item_data_dict = game_data_equipment[template_id]
					break

		if item_data_dict.get("is_twohanded", false):
			var other_hand: String = "l_hand" if slot_id == "r_hand" else "r_hand"
			for unit in owned_units_ids:
				if unit is Dictionary and unit.get("instance_id", "") == instance_id:
					var current_equipment: Dictionary = _normalize_unit_equipment(unit.get("equipment", {}))
					current_equipment.erase(other_hand)
					unit["equipment"] = current_equipment
					break

	var unit_found: bool = false
	for unit in owned_units_ids:
		if unit is Dictionary and unit.get("instance_id", "") == instance_id:
			var current_equipment: Dictionary = _normalize_unit_equipment(unit.get("equipment", {}))
			if item_id == "":
				current_equipment.erase(slot_id)
			else:
				current_equipment[slot_id] = item_id
			unit["equipment"] = current_equipment
			unit_found = true
			break

	if unit_found:
		owned_units_ids = _hydrate_owned_units(owned_units_ids)
		units_updated.emit(owned_units_ids)
		_save_snapshot(UNITS_SNAPSHOT_FILE, _snapshot_units_payload(), "equip_item")
		equip_successful.emit()
	else:
		equip_failed.emit("ERR_UNIT_NOT_FOUND")

func _equipment_exists(item_id: String) -> bool:
	if not owned_items.has("equipment"):
		return false
	for item in owned_items["equipment"]:
		if item is Dictionary and item.get("instance_id", "") == item_id:
			return true
	return false

func _normalize_unit_equipment(raw_equipment: Variant) -> Dictionary:
	if raw_equipment is Dictionary:
		return raw_equipment.duplicate(true)

	if raw_equipment is Array:
		var arr: Array = raw_equipment
		var normalized: Dictionary = {}
		if arr.size() > 0 and arr[0] != null and str(arr[0]) != "":
			normalized["r_hand"] = str(arr[0])
		if arr.size() > 1 and arr[1] != null and str(arr[1]) != "":
			normalized["l_hand"] = str(arr[1])
		return normalized

	return {}
		
func _hydrate_owned_units(units: Array) -> Array:
	var hydrated_units: Array = []
	for unit_instance in units:
		if typeof(unit_instance) != TYPE_DICTIONARY:
			hydrated_units.append(unit_instance)
			continue

		var hydrated_unit: Dictionary = {}

		# 1. Base Template Data
		var unit_id = str(unit_instance.get("unit_id", ""))
		var template_data = game_data_units.get(unit_id, {})
		hydrated_unit.merge(template_data)

		# 2. Rarity Entry Data
		var rarity = int(unit_instance.get("current_rarity", 1))
		var entries = template_data.get("entries", {})
		var rarity_entry = {}

		if entries.has(str(unit_id)):
			rarity_entry = entries[str(unit_id)]
		elif entries.has(str(rarity)):
			rarity_entry = entries[str(rarity)]

		for key in entries.keys():
			if entries[key].has("rarity") and int(entries[key]["rarity"]) == rarity:
				rarity_entry = entries[key]
				break

		hydrated_unit.merge(rarity_entry, true)

		# 3. Instance Data
		hydrated_unit.merge(unit_instance, true)
		hydrated_unit["equipment"] = _normalize_unit_equipment(unit_instance.get("equipment", {}))

		# 4. Calculate Final Stats
		hydrated_unit["final_stats"] = StatCalculator.calculate_final_stats(hydrated_unit)

		hydrated_units.append(hydrated_unit)

	return hydrated_units

func list_friends() -> Variant:
	friend_action_result.emit(false, "Friends not available in offline mode")
	return null

func add_friend(username: String) -> void:
	friend_action_result.emit(false, "Friends not available in offline mode")

func delete_friend(username: String) -> void:
	friend_action_result.emit(false, "Friends not available in offline mode")

func request_finish_mission(win_status: bool, mission_id: String, used_items: Dictionary = {}, challenge_results: Array = [], mission_drops: Array = []) -> Dictionary:
	if not win_status:
		mission_failed.emit("Mission failed")
		return {"error": "Mission failed"}

	var mission_key: String = str(mission_id)
	var progress_entry: Dictionary = {}
	var existing_entry: Variant = cleared_missions.get(mission_key, {})
	if existing_entry is Dictionary:
		progress_entry = existing_entry.duplicate(true)
	progress_entry["cleared"] = true
	cleared_missions[mission_key] = progress_entry
	latest_cleared_mission_id = _get_latest_cleared_mission_id_from_progress(cleared_missions)

	var mission_data: Dictionary = await _get_or_load_mission_data(mission_id)

	if mission_data.has("exp"):
		current_xp += int(mission_data["exp"])
		while current_xp >= next_rank_xp:
			current_xp -= next_rank_xp
			current_rank += 1
			next_rank_xp = int(next_rank_xp * 1.1)

	if mission_data.has("gil"):
		gil += int(mission_data["gil"])

	for item_id in used_items:
		var quantity: int = int(used_items[item_id])
		if owned_items.has("stackables"):
			var current_qty: int = int(owned_items["stackables"].get(item_id, 0))
			owned_items["stackables"][item_id] = max(0, current_qty - quantity)

	for drop_id in mission_drops:
		if not owned_items.has("stackables"):
			owned_items["stackables"] = {}
		var current_qty: int = int(owned_items["stackables"].get(drop_id, 0))
		owned_items["stackables"][drop_id] = current_qty + 1

	last_entered_mission_id = str(mission_id)
	await _update_last_played_dungeon_from_mission(last_entered_mission_id)

	var rewards_text: String = ""
	if mission_data.has("gil"):
		rewards_text += "Gil +%s\n" % str(int(mission_data["gil"]))
	if mission_data.has("exp"):
		rewards_text += "Rank EXP +%s\n" % str(int(mission_data["exp"]))

	_save_snapshot(MISSION_PROGRESS_SNAPSHOT_FILE, _snapshot_mission_progress_payload(), "finish_mission")
	_save_snapshot(ITEMS_SNAPSHOT_FILE, _snapshot_items_payload(), "finish_mission")
	_save_snapshot(STATS_SNAPSHOT_FILE, _snapshot_stats_payload(), "finish_mission")

	rank_updated.emit(current_rank, current_xp, next_rank_xp)
	nrg_updated.emit(current_nrg, max_nrg, seconds_until_next_nrg)
	currency_updated.emit(gil, lapis)
	items_updated.emit(owned_items)
	mission_completed.emit(rewards_text)

	return {"success": true}

func request_dungeon_missions(mission_ids: Array) -> void:
	var detailed_missions: Dictionary = {}
	for mission_id in mission_ids:
		var mission_key: String = str(mission_id)
		var mission_data: Dictionary = await _get_or_load_mission_data(mission_key)
		if not mission_data.is_empty():
			detailed_missions[mission_key] = mission_data

	for mission_id in mission_ids:
		assert(detailed_missions.has(str(mission_id)), "CRITICAL ERROR: detailed_missions is missing mission_id: " + str(mission_id))
		if not detailed_missions.has(str(mission_id)): push_error("CRITICAL ERROR: detailed_missions is missing mission_id: " + str(mission_id))
		var mission_data = detailed_missions[str(mission_id)] if detailed_missions.has(str(mission_id)) else {}
		if not mission_data.is_empty():
			game_data_missions[str(mission_id)] = mission_data # Cache it
	dungeon_missions_ready.emit(mission_ids)

func get_equipment_template_id(instance_id: String) -> String:
	assert(owned_items.has("equipment"), "CRITICAL ERROR: owned_items is missing equipment!")
	if not owned_items.has("equipment"): push_error("CRITICAL ERROR: owned_items is missing equipment!")
	var equipment_list = owned_items["equipment"] if owned_items.has("equipment") else []
	for item in equipment_list:
		if not item is Dictionary: continue
		assert(item.has("instance_id"), "CRITICAL ERROR: item is missing instance_id!")
		if not item.has("instance_id"): push_error("CRITICAL ERROR: item is missing instance_id!")
		if item["instance_id"] == instance_id:
			assert(item.has("template_id"), "CRITICAL ERROR: item is missing template_id!")
			if not item.has("template_id"): push_error("CRITICAL ERROR: item is missing template_id!")
			return item["template_id"]
	return ""

func get_available_equipment_for_slot(slot_id: String, allowed_equips: Array) -> Array:
	var available_items: Array = []
	assert(owned_items.has("equipment"), "CRITICAL ERROR: owned_items is missing equipment!")
	if not owned_items.has("equipment"): push_error("CRITICAL ERROR: owned_items is missing equipment!")
	var equipment_list = owned_items["equipment"] if owned_items.has("equipment") else []
	for item in equipment_list:
		if not item is Dictionary: continue
		assert(item.has("instance_id"), "CRITICAL ERROR: item is missing instance_id!")
		if not item.has("instance_id"): push_error("CRITICAL ERROR: item is missing instance_id!")
		var instance_id: String = item["instance_id"]

		assert(item.has("template_id"), "CRITICAL ERROR: item is missing template_id!")
		if not item.has("template_id"): push_error("CRITICAL ERROR: item is missing template_id!")
		var template_id: String = item["template_id"]

		# Materia instances are stored in the equipment collection; route them separately
		if str(item.get("item_type", "")) == "MATERIA":
			if "ability_" in slot_id and game_data_materia.has(template_id):
				var mat_data: Dictionary = game_data_materia.get(template_id, {})
				var combined: Dictionary = mat_data.duplicate()
				combined["instance_id"] = instance_id
				combined["template_id"] = template_id
				combined["item_type"] = "MATERIA"
				combined["equipped_to"] = item.get("equipped_to", null)
				available_items.append(combined)
			continue

		assert(game_data_equipment.has(template_id), "CRITICAL ERROR: game_data_equipment is missing template_id: " + template_id)
		if not game_data_equipment.has(template_id): push_error("CRITICAL ERROR: game_data_equipment is missing template_id: " + template_id)
		var item_data: Variant = game_data_equipment[template_id] if game_data_equipment.has(template_id) else null
		if not item_data: continue

		var item_data_dict: Dictionary = item_data as Dictionary

		assert(item_data_dict.has("type_id"), "CRITICAL ERROR: item_data_dict is missing type_id!")
		if not item_data_dict.has("type_id"): push_error("CRITICAL ERROR: item_data_dict is missing type_id!")
		var item_type_id: int = item_data_dict["type_id"]

		var is_valid_slot: bool = false

		assert(item_data_dict.has("slot"), "CRITICAL ERROR: item_data_dict is missing slot!")
		if not item_data_dict.has("slot"): push_error("CRITICAL ERROR: item_data_dict is missing slot!")
		var item_slot: String = item_data_dict["slot"]
		if "hand" in slot_id and (item_slot == "Weapon" or item_slot == "Shield"):
			is_valid_slot = true
		elif "head" in slot_id and item_slot == "Headgear":
			is_valid_slot = true
		elif "body" in slot_id and item_slot == "Chest":
			is_valid_slot = true
		elif "acc_" in slot_id and item_slot == "Accessory":
			is_valid_slot = true
		elif "ability_" in slot_id and item_slot == "Materia":
			is_valid_slot = true

		if not is_valid_slot: continue
		if item_type_id not in allowed_equips and item_type_id != -1: continue

		# Combine the instance wrapper data with static stats for the UI
		var combined_item: Dictionary = item_data_dict.duplicate()
		combined_item["instance_id"] = instance_id
		combined_item["template_id"] = template_id
		combined_item["equipped_to"] = item.get("equipped_to", null)

		available_items.append(combined_item)

	return available_items
