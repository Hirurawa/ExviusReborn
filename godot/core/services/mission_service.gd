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

signal mission_completed(rewards_text: String)
signal mission_failed(error_msg: String)
signal mission_progress_loaded(latest_mission_id: String)
signal dungeon_missions_ready(mission_ids: Array)

const SNAPSHOT_FILE: String = "mission_progress.json"

# First-clear ESPER rewards are not encoded in the DB MISSION.rewards yet (it only
# carries the LAPIS reward), so the 20 mission -> esper-id unlocks are seeded here
# and overlaid onto the DB rewards in `_get_or_load_mission_data_local`. Remove an
# entry once its ESPER reward lands in the database. mission_id -> summon id.
const SEEDED_ESPER_REWARDS: Dictionary = {
	"1110404": "1", "1115005": "2", "1125105": "6", "1125204": "3",
	"1135505": "7", "1230105": "5", "1325105": "4", "1425105": "10",
	"1515005": "8", "1625105": "11", "1715105": "19", "1815105": "9",
	"1920801": "15", "11215105": "16", "11315101": "12", "11425105": "14",
	"11515105": "13", "11515205": "17", "11720701": "18", "21010201": "20",
}

var cleared_missions: Dictionary = {}
var latest_cleared_mission_id: String = ""
var last_entered_mission_id: String = ""
var last_played_dungeon_name: String = ""

# Per-session cache of reconstructed mission dicts (keyed by mission id), so the
# repeated get_mission_data_local calls during a battle don't re-query the DB.
var _mission_cache: Dictionary = {}


# === Public lookups ===

func get_mission_data_local(mission_id: String) -> Dictionary:
	return _get_or_load_mission_data_local(mission_id)


# === State management ===

func reset_to_starter() -> void:
	cleared_missions = {}
	latest_cleared_mission_id = ""
	last_entered_mission_id = ""
	last_played_dungeon_name = ""


func snapshot_payload() -> Dictionary:
	return {
		"cleared_missions": cleared_missions.duplicate(true),
		"latest_cleared_mission_id": latest_cleared_mission_id
	}


func load_progress() -> void:
	var local_payload: Dictionary = _load_progress_from_local()
	cleared_missions = local_payload.get("cleared_missions", {})
	latest_cleared_mission_id = str(local_payload.get("latest_cleared_mission_id", ""))

	if latest_cleared_mission_id != "":
		await update_last_played_dungeon_from_mission(latest_cleared_mission_id)

	mission_progress_loaded.emit(latest_cleared_mission_id)


func update_last_played_dungeon_from_mission(mission_id: String) -> void:
	if mission_id == "":
		last_played_dungeon_name = ""
		return

	var mission_data: Dictionary = await _get_or_load_mission_data(mission_id)
	if mission_data.is_empty():
		return

	var dungeon_id: String = str(int(mission_data.get("dungeon_id", "")))
	if dungeon_id == "":
		return

	var dungeon_name: String = GameDatabase.get_dungeon_name(dungeon_id)
	if dungeon_name != "":
		last_played_dungeon_name = dungeon_name.replace(" ", "_")


# === Mission flow ===

func request_start_mission(mission_id: String) -> Dictionary:
	var mission_data: Dictionary = await _get_or_load_mission_data(mission_id)
	if mission_data.is_empty():
		return {"success": false, "error": "Mission not found"}

	# Exploration missions (type 2) are a separate, not-yet-implemented mode
	# (free-roam map with random encounters), not the wave-based combat the
	# battle scene provides. Refuse to launch them so they don't drop the player
	# into a scenario fight, and don't charge NRG.
	if str(mission_data.get("type", "")) == "EXPLORATION":
		return {"success": false, "error": "Exploration missions aren't available yet."}

	var cost_type: String = str(mission_data.get("cost_type", "NRG")).to_upper()
	var cost_amount: int = int(mission_data.get("cost", 0))
	if cost_type == "NRG" and cost_amount > 0:
		if PlayerProfile.current_nrg < cost_amount:
			return {"success": false, "error": "Not enough NRG to start this mission."}
		PlayerProfile.current_nrg -= cost_amount
		PlayerProfile.nrg_updated.emit(
			PlayerProfile.current_nrg,
			PlayerProfile.max_nrg,
			PlayerProfile.seconds_until_next_nrg
		)

	last_entered_mission_id = str(mission_id)
	await update_last_played_dungeon_from_mission(mission_id)
	# Stats snapshot bundles last_entered_mission_id with the profile blob.
	PlayerProfile.save_snapshot("start_mission")
	return {"success": true}


func request_finish_mission(win_status: bool, mission_id: String, used_items: Dictionary = {}, _challenge_results: Array = [], mission_drops: Array = []) -> Dictionary:
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
	cleared_missions[mission_key] = progress_entry
	latest_cleared_mission_id = _get_latest_cleared_mission_id_from_progress(cleared_missions)

	var mission_data: Dictionary = await _get_or_load_mission_data(mission_id)

	if mission_data.has("exp"):
		PlayerProfile.current_xp += int(mission_data["exp"])
		while PlayerProfile.current_xp >= PlayerProfile.next_rank_xp:
			PlayerProfile.current_xp -= PlayerProfile.next_rank_xp
			PlayerProfile.current_rank += 1
			var rank_up_nrg_bonus: int = 0
			# Update next_rank_xp from CSV data
			if PlayerProfile.rank_exp_data.has(PlayerProfile.current_rank):
				PlayerProfile.next_rank_xp = PlayerProfile.rank_exp_data[PlayerProfile.current_rank]["xp_needed"]
				PlayerProfile.max_nrg = PlayerProfile.rank_exp_data[PlayerProfile.current_rank]["energy"]
				rank_up_nrg_bonus = PlayerProfile.max_nrg
			else:
				# If rank exceeds CSV, use last known value as fallback
				if PlayerProfile.rank_exp_data.size() > 0:
					var last_rank = PlayerProfile.rank_exp_data.keys().max()
					PlayerProfile.next_rank_xp = PlayerProfile.rank_exp_data[last_rank]["xp_needed"]
					PlayerProfile.max_nrg = PlayerProfile.rank_exp_data[last_rank]["energy"]
					rank_up_nrg_bonus = PlayerProfile.max_nrg

			# Rank-up bonus: grant NRG equal to the new max NRG and allow overflow.
			if rank_up_nrg_bonus > 0:
				PlayerProfile.current_nrg += rank_up_nrg_bonus

	if mission_data.has("gil"):
		PlayerProfile.gil += int(mission_data["gil"])

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
	await update_last_played_dungeon_from_mission(last_entered_mission_id)

	var rewards_text: String = ""
	if mission_data.has("gil"):
		rewards_text += "Gil +%s\n" % str(int(mission_data["gil"]))
	if mission_data.has("exp"):
		rewards_text += "Rank EXP +%s\n" % str(int(mission_data["exp"]))

	var did_unlock_esper: bool = false
	if not was_already_cleared:
		var raw_rewards: Variant = mission_data.get("rewards", [])
		if raw_rewards is Array:
			for reward_value in raw_rewards:
				if not (reward_value is Array):
					continue

				var reward: Array = reward_value
				if reward.is_empty():
					continue

				var reward_type: String = str(reward[0]).to_upper()
				match reward_type:
					"LAPIS":
						var lapis_amount: int = 0
						if reward.size() >= 3:
							lapis_amount = int(reward[2])
						elif reward.size() >= 2:
							lapis_amount = int(reward[1])
						if lapis_amount > 0:
							PlayerProfile.lapis += lapis_amount
							rewards_text += "[First Clear] Lapis +%s\n" % str(lapis_amount)
					"ESPER":
						if reward.size() < 2:
							push_warning("Mission first-clear ESPER reward is missing summon id")
							continue
						var summon_id: String = str(reward[1]).strip_edges()
						if summon_id == "":
							push_warning("Mission first-clear ESPER reward has empty summon id")
							continue

						var unlock_result: Dictionary = EsperService.unlock_esper(summon_id)
						if bool(unlock_result.get("success", false)):
							did_unlock_esper = true
							var esper_name: String = summon_id
							var summon_template: Dictionary = StaticData.game_data_summons.get(summon_id, {})
							if not summon_template.is_empty():
								esper_name = str(summon_template.get("name", summon_id))
							rewards_text += "[First Clear] Esper unlocked: %s\n" % esper_name
						else:
							push_warning("Failed to unlock mission reward esper %s: %s" % [summon_id, str(unlock_result.get("error", "unknown_error"))])
					_:
						push_warning("Unsupported mission first-clear reward type: %s" % reward_type)

	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "finish_mission")
	Persistence.save_snapshot(InventoryService.SNAPSHOT_FILE, InventoryService.snapshot_payload(), "finish_mission")
	PlayerProfile.save_snapshot("finish_mission")
	if did_unlock_esper:
		Persistence.save_snapshot(EsperService.SNAPSHOT_FILE, EsperService.snapshot_payload(), "finish_mission")

	PlayerProfile.emit_all()
	InventoryService.emit_updated()
	mission_completed.emit(rewards_text)

	return {"success": true}


func request_dungeon_missions(mission_ids: Array) -> void:
	dungeon_missions_ready.emit(mission_ids)


# === Helpers ===

func _get_or_load_mission_data(mission_id: String) -> Dictionary:
	return _get_or_load_mission_data_local(str(mission_id))


func _get_or_load_mission_data_local(mission_id: String) -> Dictionary:
	var mission_key: String = str(mission_id)
	if _mission_cache.has(mission_key):
		return _mission_cache[mission_key]

	# Mission data now comes from the MISSION + CHALLENGE tables (was missions.json).
	var mission_data: Dictionary = GameDatabase.get_mission(mission_key)
	if mission_data.is_empty():
		return {}

	_apply_seeded_esper_reward(mission_key, mission_data)
	_mission_cache[mission_key] = mission_data
	return mission_data


# Overlays the seeded first-clear ESPER reward (not yet in the DB) onto the
# mission's reward list so esper unlocks keep working through the normal flow.
func _apply_seeded_esper_reward(mission_key: String, mission_data: Dictionary) -> void:
	if not SEEDED_ESPER_REWARDS.has(mission_key):
		return
	var rewards: Array = mission_data.get("rewards", [])
	rewards.append(["ESPER", str(SEEDED_ESPER_REWARDS[mission_key])])
	mission_data["rewards"] = rewards


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
