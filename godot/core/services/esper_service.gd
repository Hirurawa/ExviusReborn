extends Node
## EsperService — owns owned_summons array, esper progression, board/SP/skill
## unlocks, hydration, and party-assigned-esper backfill.
##
## Static-data reads go through StaticData (`game_data_summons`,
## `game_data_summons_boards`). Persistence is direct via the Persistence
## autoload + SNAPSHOT_FILE.

signal espers_updated(espers: Array)

const SNAPSHOT_FILE: String = "espers.json"
const ESPER_STAT_KEYS: Array[String] = ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]

var owned_summons: Array = []


# === State management ===

func reset_to_empty() -> void:
	owned_summons = []

func emit_updated() -> void:
	espers_updated.emit(owned_summons)

func snapshot_payload() -> Dictionary:
	var lean_espers: Array = []
	for esper in owned_summons:
		if esper is Dictionary:
			lean_espers.append(_extract_esper_lean_record(esper))

	return {
		"owned_summons": lean_espers
	}

func load_from_local() -> void:
	owned_summons = _load_from_local()

# === Public API ===

func get_esper_progression(summon_id: String) -> Dictionary:
	var index: int = _find_esper_index_by_summon_id(summon_id)
	if index < 0:
		return {}

	var record_value: Dictionary = owned_summons[index]
	return record_value.duplicate(true) if not record_value == null else {}

func get_esper_board_stat_bonuses(summon_id: String) -> Dictionary:
	var bonus: Dictionary = {}
	for stat_name in ESPER_STAT_KEYS:
		bonus[stat_name] = 0

	var normalized_summon_id: String = summon_id.strip_edges()
	if normalized_summon_id == "":
		return bonus

	var progression: Dictionary = get_esper_progression(normalized_summon_id)
	if progression.is_empty():
		return bonus

	var boards_value: Variant = StaticData.game_data_summons_boards.get(normalized_summon_id, {})
	if not (boards_value is Dictionary):
		return bonus

	var board_nodes: Dictionary = boards_value
	var unlocked_nodes: Array = _normalize_string_array(progression.get("unlocked_board_nodes", []))
	for node_id in unlocked_nodes:
		var node_value: Variant = board_nodes.get(node_id, {})
		if not (node_value is Dictionary):
			continue

		var node_data: Dictionary = node_value
		var reward_value: Variant = node_data.get("reward", null)
		if not (reward_value is Array):
			continue

		var reward: Array = reward_value
		if reward.size() < 2:
			continue

		var reward_type: String = str(reward[0]).strip_edges().to_upper()
		if not bonus.has(reward_type):
			continue

		var reward_amount: Variant = reward[1]
		if typeof(reward_amount) not in [TYPE_INT, TYPE_FLOAT]:
			continue

		bonus[reward_type] += int(reward_amount)

	return bonus

func is_esper_unlocked(summon_id: String) -> bool:
	var progression: Dictionary = get_esper_progression(summon_id)
	if progression.is_empty():
		return false
	return bool(progression.get("is_unlocked", false))

func unlock_esper(summon_id: String) -> Dictionary:
	var normalized_summon_id: String = summon_id.strip_edges()
	if normalized_summon_id == "":
		return {"success": false, "error": "ERR_INVALID_SUMMON_ID"}

	var record: Dictionary = get_esper_progression(normalized_summon_id)
	if record.is_empty():
		record = _build_default_esper_progression(normalized_summon_id)

	record["is_unlocked"] = true
	_upsert_esper_record(record)
	_rehydrate_and_emit_espers("unlock_esper")
	return {"success": true, "esper": get_esper_progression(normalized_summon_id)}

func set_esper_progression(summon_id: String, rank: int, level: int, xp: int, old_level: int = -1) -> Dictionary:
	var normalized_summon_id: String = summon_id.strip_edges()
	if normalized_summon_id == "":
		return {"success": false, "error": "ERR_INVALID_SUMMON_ID"}

	var summon_template: Dictionary = GameDatabase.get_esper(int(normalized_summon_id), rank)
	var max_rank: int = 3

	var record: Dictionary = get_esper_progression(normalized_summon_id)
	if record.is_empty():
		record = _build_default_esper_progression(normalized_summon_id)

	# Calculate SP rewards if there was a level-up
	var sp_reward: int = 0
	if old_level > 0 and level > old_level:
		sp_reward = _calculate_sp_reward(summon_template, old_level, level)

	# Check for max level to unlock the next rank
	var is_max_level: bool = level >= int(summon_template.get("maxLv"))
	
	record["is_unlocked"] = true
	record["rank"] = clampi(rank, 1, max_rank)
	record["level"] = maxi(1, level)
	record["xp"] = maxi(0, xp)
	if sp_reward > 0:
		var current_sp: int = int(record.get("current_sp", 0))
		record["current_sp"] = current_sp + sp_reward
	_upsert_esper_record(record)

	if is_max_level:
		var switch_id: String = "82%03d%d10" % [int(summon_id), rank]
		var did_unlock: bool = SwitchService.unlock_switches(switch_id, "esper_max_level")
		if did_unlock:
			print("Unlocked esper max level switch: ", switch_id)

	_rehydrate_and_emit_espers("set_esper_progression")
	return {"success": true, "esper": get_esper_progression(normalized_summon_id)}

func set_esper_sp(summon_id: String, current_sp: int) -> Dictionary:
	var normalized_summon_id: String = summon_id.strip_edges()
	var record: Dictionary = get_esper_progression(normalized_summon_id)
	if record.is_empty():
		return {"success": false, "error": "ERR_ESPER_NOT_FOUND"}

	record["current_sp"] = maxi(0, current_sp)
	_upsert_esper_record(record)
	_rehydrate_and_emit_espers("set_esper_sp")
	return {"success": true, "esper": get_esper_progression(normalized_summon_id)}

func spend_esper_sp(summon_id: String, amount: int) -> Dictionary:
	var normalized_summon_id: String = summon_id.strip_edges()
	var spend_amount: int = maxi(0, amount)

	var record: Dictionary = get_esper_progression(normalized_summon_id)
	if record.is_empty():
		return {"success": false, "error": "ERR_ESPER_NOT_FOUND"}

	var current_sp: int = int(record.get("current_sp", 0))
	if current_sp < spend_amount:
		return {"success": false, "error": "ERR_INSUFFICIENT_SP"}

	record["current_sp"] = current_sp - spend_amount
	_upsert_esper_record(record)
	_rehydrate_and_emit_espers("spend_esper_sp")
	return {"success": true, "esper": get_esper_progression(normalized_summon_id)}

func unlock_esper_skill(summon_id: String, skill_id: String) -> Dictionary:
	var normalized_summon_id: String = summon_id.strip_edges()
	var normalized_skill_id: String = skill_id.strip_edges()
	if normalized_skill_id == "":
		return {"success": false, "error": "ERR_INVALID_SKILL_ID"}

	var record: Dictionary = get_esper_progression(normalized_summon_id)
	if record.is_empty():
		return {"success": false, "error": "ERR_ESPER_NOT_FOUND"}

	var unlocked_skills: Array = _normalize_string_array(record.get("unlocked_skills", []))
	if unlocked_skills.has(normalized_skill_id):
		return {"success": false, "error": "ERR_SKILL_ALREADY_UNLOCKED"}

	unlocked_skills.append(normalized_skill_id)
	record["unlocked_skills"] = unlocked_skills
	_upsert_esper_record(record)
	_rehydrate_and_emit_espers("unlock_esper_skill")
	return {"success": true, "esper": get_esper_progression(normalized_summon_id)}

func unlock_esper_board_node(summon_id: String, node_id: String, sp_cost: int = 0, reward_skill_id: String = "") -> Dictionary:
	var normalized_summon_id: String = summon_id.strip_edges()
	var normalized_node_id: String = node_id.strip_edges()
	if normalized_node_id == "":
		return {"success": false, "error": "ERR_INVALID_NODE_ID"}

	var record: Dictionary = get_esper_progression(normalized_summon_id)
	if record.is_empty():
		return {"success": false, "error": "ERR_ESPER_NOT_FOUND"}

	var unlocked_nodes: Array = _normalize_string_array(record.get("unlocked_board_nodes", []))
	if unlocked_nodes.has(normalized_node_id):
		return {"success": false, "error": "ERR_NODE_ALREADY_UNLOCKED"}

	var spend_result: Dictionary = {}
	if sp_cost > 0:
		spend_result = spend_esper_sp(normalized_summon_id, sp_cost)
		if not bool(spend_result.get("success", false)):
			return spend_result
		record = get_esper_progression(normalized_summon_id)

	unlocked_nodes.append(normalized_node_id)
	record["unlocked_board_nodes"] = unlocked_nodes

	var normalized_reward_skill_id: String = reward_skill_id.strip_edges()
	if normalized_reward_skill_id != "":
		var unlocked_skills: Array = _normalize_string_array(record.get("unlocked_skills", []))
		if not unlocked_skills.has(normalized_reward_skill_id):
			unlocked_skills.append(normalized_reward_skill_id)
		record["unlocked_skills"] = unlocked_skills

	_upsert_esper_record(record)
	_rehydrate_and_emit_espers("unlock_esper_board_node")
	return {"success": true, "esper": get_esper_progression(normalized_summon_id)}

func reset_esper_board_progression(summon_id: String) -> Dictionary:
	var normalized_summon_id: String = summon_id.strip_edges()
	if normalized_summon_id == "":
		return {"success": false, "error": "ERR_INVALID_SUMMON_ID"}

	var record: Dictionary = get_esper_progression(normalized_summon_id)
	if record.is_empty():
		return {"success": false, "error": "ERR_ESPER_NOT_FOUND"}

	var current_sp: int = int(record.get("current_sp", 0))
	var unlocked_nodes: Array = _normalize_string_array(record.get("unlocked_board_nodes", []))
	var refund_sp: int = _calculate_esper_board_sp_refund(normalized_summon_id, unlocked_nodes)
	record["current_sp"] = current_sp + refund_sp
	record["unlocked_board_nodes"] = []
	record["unlocked_skills"] = []

	_upsert_esper_record(record)
	_rehydrate_and_emit_espers("reset_esper_board_progression")
	return {"success": true, "esper": get_esper_progression(normalized_summon_id)}


# === Hydration ===

func hydrate_owned_espers(espers: Array) -> Array:
	return _hydrate_owned_espers(espers)


# === Internals ===

func _extract_esper_lean_record(hydrated_esper: Dictionary) -> Dictionary:
	return {
		"summon_id": str(hydrated_esper.get("summon_id", "")).strip_edges(),
		"is_unlocked": bool(hydrated_esper.get("is_unlocked", false)),
		"rank": maxi(1, int(hydrated_esper.get("rank", 1))),
		"level": maxi(1, int(hydrated_esper.get("level", 1))),
		"xp": maxi(0, int(hydrated_esper.get("xp", 0))),
		"current_sp": maxi(0, int(hydrated_esper.get("current_sp", 0))),
		"unlocked_skills": _normalize_string_array(hydrated_esper.get("unlocked_skills", [])),
		"unlocked_board_nodes": _normalize_string_array(hydrated_esper.get("unlocked_board_nodes", []))
	}

func _build_default_esper_progression(summon_id: String) -> Dictionary:
	return {
		"summon_id": summon_id,
		"is_unlocked": false,
		"rank": 1,
		"level": 1,
		"xp": 0,
		"current_sp": 0,
		"unlocked_skills": [],
		"unlocked_board_nodes": []
	}

func _calculate_sp_reward(summon_template: Dictionary, old_level: int, new_level: int) -> int:
	# Calculate SP rewards based on cp_pattern when esper levels up
	# cp_pattern[N] = SP gained when reaching level N+1 (0-indexed array)

	if new_level <= old_level:
		return 0

	var cp_pattern_value: Variant = summon_template.get("cpPattern", []).split(',')
	var cp_pattern: Array = cp_pattern_value
	var total_sp_reward: int = 0

	# Loop through each level from old_level + 1 to new_level
	# cp_pattern[level - 1] gives the SP for reaching that level
	for level in range(old_level + 1, new_level + 1):
		var pattern_index: int = level - 1
		if pattern_index >= 0 and pattern_index < cp_pattern.size():
			var sp_for_level: Variant = int(cp_pattern[pattern_index])
			if sp_for_level is int:
				total_sp_reward += sp_for_level
			else:
				total_sp_reward += maxi(0, int(sp_for_level))
	return total_sp_reward

func _normalize_esper_record(raw_record: Variant) -> Dictionary:
	if not (raw_record is Dictionary):
		return {}

	var payload: Dictionary = raw_record
	var summon_id: String = str(payload.get("summon_id", "")).strip_edges()
	if summon_id == "":
		return {}

	var normalized: Dictionary = _build_default_esper_progression(summon_id)
	normalized["is_unlocked"] = bool(payload.get("is_unlocked", false))
	normalized["rank"] = maxi(1, int(payload.get("rank", 1)))
	normalized["level"] = maxi(1, int(payload.get("level", 1)))
	normalized["xp"] = maxi(0, int(payload.get("xp", 0)))
	normalized["current_sp"] = maxi(0, int(payload.get("current_sp", 0)))
	normalized["unlocked_skills"] = _normalize_string_array(payload.get("unlocked_skills", []))
	normalized["unlocked_board_nodes"] = _normalize_string_array(payload.get("unlocked_board_nodes", []))
	return normalized

func _normalize_espers_payload(raw_payload: Variant) -> Array:
	if not (raw_payload is Dictionary):
		return []

	var payload: Dictionary = raw_payload
	var records_value: Variant = payload.get("owned_summons", [])
	if not (records_value is Array):
		return []

	var source_records: Array = records_value
	var by_summon_id: Dictionary = {}
	for record_value in source_records:
		var normalized: Dictionary = _normalize_esper_record(record_value)
		if normalized.is_empty():
			continue
		by_summon_id[normalized["summon_id"]] = normalized

	var normalized_records: Array = []
	for summon_id in by_summon_id.keys():
		normalized_records.append(by_summon_id[summon_id])

	normalized_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_id: String = str(a.get("summon_id", ""))
		var b_id: String = str(b.get("summon_id", ""))
		if a_id.is_valid_int() and b_id.is_valid_int():
			return int(a_id) < int(b_id)
		return a_id < b_id
	)

	return normalized_records

func _normalize_string_array(raw_values: Variant) -> Array:
	if not (raw_values is Array):
		return []

	var normalized: Array = []
	for value in raw_values:
		var normalized_value: String = str(value).strip_edges()
		if normalized_value == "":
			continue
		if normalized.has(normalized_value):
			continue
		normalized.append(normalized_value)

	return normalized

func _load_from_local() -> Array:
	var envelope: Dictionary = Persistence.load_snapshot(SNAPSHOT_FILE)
	if envelope.is_empty():
		return []

	var data: Variant = envelope.get("data", {})
	if not (data is Dictionary):
		return []

	var lean_espers: Array = _normalize_espers_payload(data)
	if lean_espers.is_empty():
		return []

	return _hydrate_owned_espers(lean_espers)

func _find_esper_index_by_summon_id(summon_id: String) -> int:
	for i in range(owned_summons.size()):
		var record_value: Variant = owned_summons[i]
		if str(record_value.get("summon_id", "")) == summon_id:
			return i

	return -1

func _rehydrate_and_emit_espers(source_event: String) -> void:
	owned_summons = _hydrate_owned_espers(_normalize_espers_payload(snapshot_payload()))
	espers_updated.emit(owned_summons)
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), source_event)

func _upsert_esper_record(record: Dictionary) -> void:
	var normalized: Dictionary = _normalize_esper_record(record)
	if normalized.is_empty():
		return

	var existing_index: int = _find_esper_index_by_summon_id(str(normalized.get("summon_id", "")))
	if existing_index >= 0:
		owned_summons[existing_index] = normalized
	else:
		owned_summons.append(normalized)

func _calculate_esper_board_sp_refund(summon_id: String, unlocked_nodes: Array) -> int:
	var board_value: Variant = StaticData.game_data_summons_boards.get(summon_id, {})
	if not (board_value is Dictionary):
		return 0

	var board_nodes: Dictionary = board_value
	var total_refund: int = 0
	for node_id_value in unlocked_nodes:
		var node_id: String = str(node_id_value)
		var node_value: Variant = board_nodes.get(node_id, {})
		if not (node_value is Dictionary):
			continue

		var cost_value: Variant = (node_value as Dictionary).get("cost", {})
		if not (cost_value is Dictionary):
			continue

		total_refund += maxi(0, int((cost_value as Dictionary).get("SP", 0)))

	return total_refund

func _hydrate_owned_espers(espers: Array) -> Array:
	var hydrated_espers: Array = []
	for esper_value in espers:
		if not (esper_value is Dictionary):
			continue

		var normalized_record: Dictionary = _normalize_esper_record(esper_value)
		if normalized_record.is_empty():
			continue

		var summon_id: String = str(normalized_record.get("summon_id", ""))
		var template_data: Dictionary = GameDatabase.get_esper(int(summon_id), esper_value.get("rank"))
		var hydrated: Dictionary = template_data.duplicate(true)
		hydrated["summon_id"] = summon_id
		hydrated["progression"] = normalized_record.duplicate(true)
		hydrated.merge(normalized_record, true)
		hydrated_espers.append(hydrated)

	return hydrated_espers
