extends Node
## MissionService — owns mission progress (cleared map + latest cleared id +
## last entered + last played dungeon name), mission lookup / normalization,
## map-selection helpers, and the start/finish/dungeon flow.
##
## Cross-service touches:
##   - request_start_mission consumes NRG via PlayerProfile (writes to
##     DataManager scalars, which forward to PlayerProfile).
##   - request_finish_mission grants XP/gil/lapis (PlayerProfile via DataManager
##     scalars), mutates owned_items.stackables (InventoryService dict), unlocks
##     espers (via EsperService), and triggers snapshots through Persistence
##     directly (esper blob via EsperService; stats blob still bundled with
##     DataManager facade).

signal mission_completed(result: Dictionary)
signal mission_failed(error_msg: String)
signal mission_progress_loaded(latest_mission_id: String)
signal dungeon_missions_ready(mission_ids: Array)

const SNAPSHOT_FILE: String = "mission_progress.json"


var cleared_missions: Dictionary = {}
var latest_cleared_mission_id: String = ""
var last_entered_mission_id: String = ""

# Per-session cache of reconstructed mission dicts (keyed by mission id), so the
# repeated get_mission_data calls during a battle don't re-query the DB.
var _mission_cache: Dictionary = {}


# === State management ===

func reset_to_starter() -> void:
	cleared_missions = {}
	latest_cleared_mission_id = ""
	last_entered_mission_id = ""


func snapshot_payload() -> Dictionary:
	return {
		"cleared_missions": cleared_missions.duplicate(true),
		"latest_cleared_mission_id": latest_cleared_mission_id
	}


func load_progress() -> void:
	var local_payload: Dictionary = _load_progress_from_local()
	cleared_missions = local_payload.get("cleared_missions", {})
	latest_cleared_mission_id = str(local_payload.get("latest_cleared_mission_id", ""))

	mission_progress_loaded.emit(latest_cleared_mission_id)


# === Mission flow ===

func request_start_mission(mission_id: String) -> Dictionary:
	var mission_data: Dictionary = get_mission_data(mission_id)
	if mission_data.is_empty():
		return {"success": false, "error": "Mission not found"}

	# Exploration missions (type 2) are a separate, not-yet-implemented mode
	# (free-roam map with random encounters), not the wave-based combat the
	# battle scene provides. Refuse to launch them so they don't drop the player
	# into a scenario fight, and don't charge NRG.
	# type=2 AND waveCount=0 - genuine explorations — every one is named "… - Exploration" or a story equivalent
	# type=2 AND waveCount>=1 - Siren's Tower Top Floor, Bewitcher's Trial, and every "Trial of the …" esper unlock Not really exploration missions. They are regular missions
	#if str(mission_data.get("type", "")) == "EXPLORATION":
		#return {"success": false, "error": "Exploration missions aren't available yet."}

	var cost_type: String = str(mission_data.get("cost_type", "NRG")).to_upper()
	var cost_amount: int = int(mission_data.get("cost", 0))
	if cost_type == "NRG" and cost_amount > 0:
		if PlayerProfile.current_nrg < cost_amount:
			return {"success": false, "error": "Not enough NRG to start this mission."}
		PlayerProfile.deduct_nrg(cost_amount)

	last_entered_mission_id = str(mission_id)

	# Stats snapshot bundles last_entered_mission_id with the profile blob.
	# We will handle it by creating a method in PlayerProfile that does this and saves.
	PlayerProfile.set_last_entered_mission(mission_id)
	return {"success": true}


## Finishes a mission. `unit_exp` and `battle_gil` are what the battle accumulated
## from defeated enemies (BattleManager.mission_unit_exp / mission_gil): every unit
## in the party that ran the mission gains the full unit EXP, and the battle gil is
## paid out on top of the mission's own gil reward.
func request_finish_mission(win_status: bool, mission_id: String, used_items: Dictionary = {}, challenge_results: Array = [], mission_drops: Array = [], unit_exp: int = 0, battle_gil: int = 0) -> Dictionary:
	if not win_status:
		mission_failed.emit("Mission failed")
		return {"error": "Mission failed"}

	var mission_key: String = str(mission_id)
	var progress_entry: Dictionary = {}
	var existing_entry: Variant = cleared_missions.get(mission_key, {})
	var was_already_cleared: bool = false
	if existing_entry is Dictionary:
		progress_entry = existing_entry.duplicate(true)
		was_already_cleared = bool(existing_entry.get("cleared", false))
	progress_entry["cleared"] = true

	var mission_data: Dictionary = get_mission_data(mission_id)
	var challenges: Array = mission_data.get("challenges", [])
	var previous_objectives: Array = progress_entry.get("objectives", [])
	var objectives: Array = []
	objectives.resize(challenges.size())
	for index in range(challenges.size()):
		var previously_completed: bool = index < previous_objectives.size() and bool(previous_objectives[index])
		var completed_now: bool = index < challenge_results.size() and bool(challenge_results[index])
		objectives[index] = previously_completed or completed_now
		if not previously_completed and completed_now:
			_grant_reward(challenges[index].get("reward"))
			pass
	progress_entry["objectives"] = objectives
	cleared_missions[mission_key] = progress_entry
	latest_cleared_mission_id = _get_latest_cleared_mission_id_from_progress(cleared_missions)

	var rank_before: int = PlayerProfile.current_rank
	var xp_before: int = PlayerProfile.current_xp
	if mission_data.has("exp"):
		PlayerProfile.add_xp(int(mission_data["exp"]))

	# Total gil paid out: the mission's fixed clear reward plus what the defeated
	# enemies dropped during the battle.
	var mission_gil: int = maxi(0, int(mission_data.get("gil", 0)))
	var granted_gil: int = mission_gil + maxi(0, battle_gil)
	if granted_gil > 0:
		PlayerProfile.add_gil(granted_gil)

	# Combat EXP earned during the battle, granted to every party member.
	var granted_unit_exp: int = maxi(0, unit_exp)
	var unit_exp_awards: Array = []
	if granted_unit_exp > 0:
		var award_result: Dictionary = UnitService.award_battle_exp(_active_party_instance_ids(), granted_unit_exp)
		unit_exp_awards = award_result.get("awarded", [])

	var owned_items: Dictionary = InventoryService.owned_items
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

	var rewards_text: String = ""
	if granted_gil > 0:
		rewards_text += "Gil +%s\n" % str(granted_gil)
	if mission_data.has("exp"):
		rewards_text += "Rank EXP +%s\n" % str(int(mission_data["exp"]))
	if granted_unit_exp > 0:
		rewards_text += "Unit EXP +%s\n" % str(granted_unit_exp)

	var any_switches_unlocked: bool = false
	if mission_data.has("open_switches"):
		var switches_str: String = str(mission_data["open_switches"])
		any_switches_unlocked = SwitchService.unlock_switches(switches_str, "finish_mission")

		for switch in switches_str.split(','):
			var unlock = GameDatabase.get_map_event_switch_unlock(int(mission_data["dungeon_id"]), int(switch))
			if unlock:
				SwitchService.unlock_switches(str(unlock), "map_event")

		# Parse switches for esper unlocks (Format: 82{beastId}100, length 8)
		# Only check for new unlocks if mission wasn't already cleared.
		if not was_already_cleared and any_switches_unlocked:
			var switch_parts: PackedStringArray = switches_str.split(",")
			for part in switch_parts:
				var switch_id: String = part.strip_edges()
				if switch_id.length() == 8 and switch_id.begins_with("82"):
					var beast_id_str: String = switch_id.substr(2, 3)
					var summon_id: String = str(int(beast_id_str)) # parse as int to drop leading zeros, then back to string

					if switch_id.ends_with("100"):
						var unlock_result: Dictionary = EsperService.unlock_esper(summon_id)
						if bool(unlock_result.get("success", false)):
							var esper_name: String = summon_id
							var summon_template: Dictionary = GameDatabase.get_esper(int(summon_id))
							if not summon_template.is_empty():
								esper_name = str(summon_template.get("name", summon_id))
							rewards_text += "[First Clear] Esper unlocked: %s\n" % esper_name
						else:
							push_warning("Failed to unlock mission reward esper %s (from switch %s): %s" % [summon_id, switch_id, str(unlock_result.get("error", "unknown_error"))])
					elif switch_id.ends_with("200") or switch_id.ends_with("300"):
						var new_rank: int = 2 if switch_id.ends_with("200") else 3
						# Only process if esper is already unlocked
						if EsperService.is_esper_unlocked(summon_id):
							var progression: Dictionary = EsperService.get_esper_progression(summon_id)
							var current_rank: int = int(progression.get("rank", 1))
							if current_rank < new_rank:
								var rank_up_result: Dictionary = EsperService.set_esper_progression(summon_id, new_rank, 1, 0, -1)
								if bool(rank_up_result.get("success", false)):
									var esper_name: String = summon_id
									var summon_template: Dictionary = GameDatabase.get_esper(int(summon_id))
									if not summon_template.is_empty():
										esper_name = str(summon_template.get("name", summon_id))
									# Only display the name if it is unlocked, plus append rank upgrade message
									rewards_text += "[First Clear] Esper %s reached Rank %d!\n" % [esper_name, new_rank]
								else:
									push_warning("Failed to rank up esper %s to rank %d (from switch %s): %s" % [summon_id, new_rank, switch_id, str(rank_up_result.get("error", "unknown_error"))])
						else:
							push_warning("Tried to rank up locked esper %s to rank %d (from switch %s)" % [summon_id, new_rank, switch_id])

	if not was_already_cleared:
		var raw_rewards: Variant = mission_data.get("rewards", [])
		for reward_value in raw_rewards:
			_grant_reward(reward_value)

	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "finish_mission")
	PlayerProfile.emit_all()
	InventoryService.emit_updated()
	var result: Dictionary = {
		"success": true,
		"mission_id": mission_key,
		"mission_name": str(mission_data.get("name", mission_key)),
		"rank_exp": int(mission_data.get("exp", 0)),
		"unit_exp": granted_unit_exp,
		"unit_exp_awards": unit_exp_awards,
		"gil": granted_gil,
		"mission_gil": mission_gil,
		"battle_gil": maxi(0, battle_gil),
		"rank_before": rank_before,
		"xp_before": xp_before,
		"rank_after": PlayerProfile.current_rank,
		"xp_after": PlayerProfile.current_xp,
		"drops": mission_drops.duplicate(),
		"challenges": challenges,
		"objectives": objectives,
		"rewards_text": rewards_text,
	}
	mission_completed.emit(result)

	return result


func _grant_reward(reward: Array):
	# Shared with town treasure chests -- see core/reward_granter.gd.
	var info: Dictionary = RewardGranter.grant(reward)
	print("GRANT %s: %s x%d" % [info.get("type", ""), info.get("name", ""), int(info.get("amount", 0))])


## Instance ids of the party that ran the mission, in slot order (empty slots are
## skipped). Mirrors the party BattleManager builds when it starts a battle:
## the active party, falling back to the first saved one.
func _active_party_instance_ids() -> Array:
	if PartyService.parties.is_empty():
		return []

	var party_units: Array = []
	var active_party: Dictionary = PartyService.get_active_party()
	if not active_party.is_empty():
		party_units = active_party.get("units", [])
	else:
		var fallback_party: Variant = PartyService.parties[0]
		if fallback_party is Dictionary:
			party_units = fallback_party.get("units", [])
		elif fallback_party is Array:
			party_units = fallback_party

	var instance_ids: Array = []
	for unit_value in party_units:
		var instance_id: String = str(unit_value)
		if instance_id != "":
			instance_ids.append(instance_id)
	return instance_ids


func request_dungeon_missions(mission_ids: Array) -> void:
	dungeon_missions_ready.emit(mission_ids)


# === Helpers ===

func get_mission_data(mission_id: String) -> Dictionary:
	var mission_key: String = str(mission_id)
	if _mission_cache.has(mission_key):
		return _mission_cache[mission_key]

	# Mission data now comes from the MISSION + CHALLENGE tables (was missions.json).
	var mission_data: Dictionary = GameDatabase.get_mission(mission_key)
	if mission_data.is_empty():
		return {}

	_mission_cache[mission_key] = mission_data
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


func _load_progress_from_local() -> Dictionary:
	var envelope: Dictionary = Persistence.load_snapshot(SNAPSHOT_FILE)
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
