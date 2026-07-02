extends Node
## AccountService — owns the local "account" identity (username, account_info
## placeholder) and the session-control flow (authenticate / logout
## / update_account). Also re-emits the data_loaded signal that downstream UI
## listens for once the orchestrator finishes hydrating all domains.
##
## State previously held by DataManager that now lives here:
##   - current_username, account_info
##   - account_updated / login_success / login_failed
##     data_loaded signals
##   - authenticate, logout, update_account, _derive_username_from_email
##
## The orchestrators `start_new_local_game` and `load_local_game` (with helper
## `load_initial_data` + `save_all_snapshots`) also live here since they touch
## every domain and finish by emitting `data_loaded` / `account_updated`.

signal data_loaded
signal login_success
signal login_failed(error_code: int)
signal account_updated(username: String)

var current_username: String = ""
var account_info = null

func authenticate(email: String, _password: String) -> void:
	await load_initial_data(email)
	login_success.emit()

func logout() -> void:
	account_info = null
	MissionService.last_entered_mission_id = ""
	MissionService.last_played_dungeon_name = ""
	PartyService.selected_party_index = 0

func update_account(new_username: String) -> bool:
	current_username = new_username
	# Stats snapshot bundles username with profile data; resave the stats blob.
	PlayerProfile.save_snapshot("update_account")
	account_updated.emit(current_username)
	return true


func derive_username_from_email(email: String) -> String:
	if email == "":
		return "Player"
	var at_index: int = email.find("@")
	if at_index <= 0:
		return email
	return email.substr(0, at_index)


# === Save lifecycle orchestration ===

func list_local_saves() -> Array:
	return Persistence.list_local_saves()


func get_continue_save() -> Dictionary:
	return Persistence.get_most_recent_save()


func delete_local_save(save_id: String) -> Dictionary:
	var trimmed_id: String = save_id.strip_edges()
	if trimmed_id == "":
		return {"success": false, "error_message": "Missing save id."}
	var removed: bool = Persistence.delete_local_save(trimmed_id)
	if not removed:
		return {"success": false, "error_message": "Save not found."}
	return {"success": true, "save_id": trimmed_id}


func start_new_local_game(username: String) -> Dictionary:
	_dbg("SNG: enter")
	var normalized_username: String = username.strip_edges()
	if normalized_username == "":
		return {"success": false, "error_message": "Please enter a save name."}

	_dbg("SNG: before StaticData.ensure_ready")
	await StaticData.ensure_ready()
	_dbg("SNG: after StaticData.ensure_ready")
	Persistence.active_local_save_id = Persistence.normalize_local_save_id(normalized_username)

	_dbg("SNG: before UnitService.reset_to_starter")
	if not UnitService.reset_to_starter():
		return {"success": false, "error_message": "Failed to initialize starter units."}
	_dbg("SNG: after UnitService.reset_to_starter")

	PlayerProfile.reset_to_starter()
	_dbg("SNG: after PlayerProfile.reset_to_starter")
	MissionService.last_entered_mission_id = ""
	MissionService.last_played_dungeon_name = ""
	current_username = normalized_username

	InventoryService.reset_to_starter()
	_dbg("SNG: after InventoryService.reset_to_starter")
	CombatItemsService.reset_to_empty()
	_dbg("SNG: after CombatItemsService.reset_to_empty")
	MissionService.cleared_missions = {}
	MissionService.latest_cleared_mission_id = ""
	EsperService.reset_to_empty()
	_dbg("SNG: after EsperService.reset_to_empty")
	PartyService.reset_to_starter(PartyService.build_default_parties(UnitService.STARTER_RAIN_INSTANCE_ID, UnitService.STARTER_LASSWELL_INSTANCE_ID))
	_dbg("SNG: after PartyService.reset_to_starter")

	save_all_snapshots("new_local_game")
	_dbg("SNG: after save_all_snapshots")
	Persistence.upsert_save_index_entry(Persistence.active_local_save_id, current_username)

	PlayerProfile.emit_all()
	_dbg("SNG: after PlayerProfile.emit_all")
	InventoryService.emit_updated()
	CombatItemsService.emit_loaded()
	UnitService.emit_updated()
	EsperService.emit_updated()
	PartyService.emit_all()
	_dbg("SNG: after all emits")
	account_updated.emit(current_username)
	data_loaded.emit()
	_dbg("SNG: exit success")

	return {"success": true, "save_id": Persistence.active_local_save_id}

func _dbg(msg: String) -> void:
	if not OS.is_debug_build():
		return
	var mb: float = float(OS.get_static_memory_usage()) / 1048576.0
	print("[DBG] %-44s static=%.1fMB" % [msg, mb])


func load_local_game(username: String) -> Dictionary:
	var normalized_username: String = username.strip_edges()
	if normalized_username == "":
		return {"success": false, "error_message": "Please enter a save name."}

	await StaticData.ensure_ready()
	var resolved_save_id: String = Persistence.set_active_save(normalized_username)

	var envelope: Dictionary = Persistence.load_snapshot(PlayerProfile.SNAPSHOT_FILE)
	if envelope.is_empty() and Persistence.legacy_snapshot_exists():
		Persistence.migrate_legacy_snapshots_to_active_save()
		envelope = Persistence.load_snapshot(PlayerProfile.SNAPSHOT_FILE)

	if envelope.is_empty():
		return {"success": false, "error_message": "No save found with that name."}

	await load_initial_data(normalized_username)
	Persistence.upsert_save_index_entry(resolved_save_id, current_username if current_username != "" else normalized_username)
	return {"success": true, "save_id": resolved_save_id}


func save_all_snapshots(source_event: String) -> void:
	PlayerProfile.save_snapshot(source_event)
	Persistence.save_snapshot(InventoryService.SNAPSHOT_FILE, InventoryService.snapshot_payload(), source_event)
	Persistence.save_snapshot(CombatItemsService.SNAPSHOT_FILE, CombatItemsService.snapshot_payload(), source_event)
	Persistence.save_snapshot(UnitService.SNAPSHOT_FILE, UnitService.snapshot_payload(), source_event)
	Persistence.save_snapshot(EsperService.SNAPSHOT_FILE, EsperService.snapshot_payload(), source_event)
	Persistence.save_snapshot(PartyService.SNAPSHOT_FILE, PartyService.snapshot_payload(), source_event)
	Persistence.save_snapshot(MissionService.SNAPSHOT_FILE, MissionService.snapshot_payload(), source_event)
	Persistence.save_snapshot(SwitchService.SNAPSHOT_FILE, SwitchService.snapshot_payload(), source_event)


func load_initial_data(email: String) -> void:
	await StaticData.ensure_ready()

	var stats: Dictionary = PlayerProfile.load_stats_from_local()

	# Load rank progression data from rank_exp.json
	PlayerProfile.ensure_rank_exp_loaded()

	# Apply stats with safe defaults
	PlayerProfile.current_rank = int(stats.get("rank", 1))
	PlayerProfile.current_xp = int(stats.get("xp", 0))
	PlayerProfile.next_rank_xp = int(stats.get("next_rank_xp", 100))
	PlayerProfile.current_nrg = int(stats.get("current_nrg", 41))
	PlayerProfile.max_nrg = int(stats.get("max_nrg", 41))
	PlayerProfile.nrg_regen_rate_seconds = int(stats.get("nrg_regen_rate_seconds", 300))
	PlayerProfile.seconds_until_next_nrg = float(stats.get("seconds_until_next_nrg", 0.0))
	MissionService.last_entered_mission_id = str(stats.get("last_entered_mission_id", ""))
	PlayerProfile.gil = int(stats.get("gil", 0))
	PlayerProfile.lapis = int(stats.get("lapis", 0))

	var m_progress = stats.get("monster_kill_progress", {})
	if typeof(m_progress) == TYPE_DICTIONARY:
		PlayerProfile.monster_kill_progress = m_progress
	else:
		PlayerProfile.monster_kill_progress = {}

	# Normalize progression values only when save data is missing/invalid.
	if PlayerProfile.next_rank_xp <= 0 or PlayerProfile.max_nrg <= 0:
		if not PlayerProfile.rank_exp_data.is_empty():
			if PlayerProfile.rank_exp_data.has(PlayerProfile.current_rank):
				PlayerProfile.next_rank_xp = int(PlayerProfile.rank_exp_data[PlayerProfile.current_rank].get("xp_needed", PlayerProfile.next_rank_xp))
				PlayerProfile.max_nrg = int(PlayerProfile.rank_exp_data[PlayerProfile.current_rank].get("energy", PlayerProfile.max_nrg))
			else:
				var fallback_rank: int = int(PlayerProfile.rank_exp_data.keys().max())
				PlayerProfile.next_rank_xp = int(PlayerProfile.rank_exp_data[fallback_rank].get("xp_needed", PlayerProfile.next_rank_xp))
				PlayerProfile.max_nrg = int(PlayerProfile.rank_exp_data[fallback_rank].get("energy", PlayerProfile.max_nrg))
	current_username = str(stats.get("username", ""))
	if MissionService.last_entered_mission_id != "":
		MissionService.update_last_played_dungeon_from_mission(MissionService.last_entered_mission_id)
	else:
		MissionService.last_played_dungeon_name = ""

	await MissionService.load_progress()
	SwitchService.load_progress()
	PlayerProfile.emit_all()

	InventoryService.load_from_local()
	InventoryService.emit_updated()

	CombatItemsService.load_from_local()
	CombatItemsService.emit_loaded()

	UnitService.load_from_local()
	UnitService.emit_updated()

	EsperService.load_from_local()
	EsperService.emit_updated()

	PartyService.load_from_local()
	EsperService.ensure_party_assigned_espers_owned(PartyService.parties)
	PartyService.emit_all()

	if current_username == "":
		current_username = derive_username_from_email(email)
	account_updated.emit(current_username)

	save_all_snapshots("initial_load")

	data_loaded.emit()
