extends Node

signal battle_state_ready
signal enemy_hp_changed(enemy_index: int, new_hp: int, max_hp: int, hp_percent: int)
signal turn_changed(new_turn: int)
signal unit_stats_updated(index: int, unit_name: String, cur_hp: int, max_hp: int, cur_mp: int, max_mp: int, cur_limit: int, max_limit: int)
signal attack_landed(attacker_team: String, attacker_index: int, target_team: String, target_index: int, damage: int, chain_count: int, receipt_type: String)
signal unit_acted(index: int)
signal unit_action_started(unit_index: int, action: CombatAction)
signal action_queued(unit_index: int, action: CombatAction, action_id: String)
signal enemy_action_started(enemy_index: int, action: CombatAction)
signal mission_cleared
signal mission_failed

signal item_refunded(item_id: String)
signal wave_changed(current_wave: int, total_waves: int)
signal wave_transition_started(current_wave: int, next_wave: int, total_waves: int)
signal item_dropped(enemy_index: int, item_id: String)
signal limit_crystal_dropped(enemy_index: int, target_unit_index: int)

enum BattleState { INIT, PLAYER_TURN, RESOLVING_TURN, ENEMY_TURN, BATTLE_OVER }
enum CombatAction { ATTACK, DEFEND, SKILL, ITEM }

const ENEMY_ATTACK_DELAY_FRAMES: int = 60
const LIMIT_CRYSTAL_DROP_CHANCE: float = 0.20
const LIMIT_CRYSTAL_GAIN: int = 1
const COVER_STATE_AOE: String = "is_aoe_covering"
const COVER_STATE_ST: String = "is_st_covering"
const COVER_STATE_MITIGATION: String = "active_cover_mitigation"

var action_processor
var result_processor
var current_state: BattleState = BattleState.INIT
var player_units_acted_this_turn: Array = []
var current_battle_frame: int = 0
var pending_hits: Array[Dictionary] = []

var player_units: Array = []
var enemy_units: Array = []

var party_data: Array = []
var turn_count: int = 1

var is_transitioning: bool = false

var current_wave: int = 1
var total_waves: int = 1
var current_mission_id: String = ""
var mission_drops: Array[String] = []
var used_items: Dictionary = {}
var challenge_results: Array[bool] = []

func _ready() -> void:
	# 1. Instantiate the script purely in code
	action_processor = preload("res://features/battle/logic/action_processor.gd").new()
	result_processor = preload("res://features/battle/logic/result_processor.gd").new()
	
	# 2. Give it a name so it shows up cleanly in the debugger
	action_processor.name = "ActionProcessor"
	result_processor.name = "ResultProcessor"
	
	# 3. Add it as a child to the BattleManager
	add_child(action_processor)
	add_child(result_processor)

func _physics_process(_delta: float) -> void:
	if current_state != BattleState.PLAYER_TURN and current_state != BattleState.ENEMY_TURN:
		return

	current_battle_frame += 1

	for i in range(pending_hits.size() - 1, -1, -1):
		var hit: Dictionary = pending_hits[i]
		if hit.get("execute_on_frame", 0) <= current_battle_frame:
			var target_team: String = hit.get("target_team", "enemy")
			var target_index: int = hit.get("target_index", 0)
			var damage: int = hit.get("amount", 0)
			var attacker_team: String = hit.get("attacker_team", "player")
			var attacker_index: int = hit.get("attacker_index", 0)

			var target_array = enemy_units if target_team == "enemy" else party_data
			var final_damage: int = damage
			var chain_count_emitted: int = 0

			if target_index >= 0 and target_index < target_array.size():
				var target = target_array[target_index]
				if not target.is_empty():
					var frame_gap = current_battle_frame - target.get("last_hit_frame", -100)
					var current_attacker = attacker_index
					var base_damage = damage

					# Check for Chain Break
					if frame_gap > 20 or current_attacker == target.get("last_attacker_index", -1):
						target["chain_count"] = 0
					# Check for Chain Build
					elif frame_gap <= 20 and current_attacker != target.get("last_attacker_index", -1):
						target["chain_count"] += 1
						target["chain_count"] = min(target["chain_count"], 10)

					var chain_multiplier = 1.0 + (target["chain_count"] * 0.3)
					final_damage = int(base_damage * chain_multiplier)

					if str(hit.get("type", "")).to_lower() == "damage":
						final_damage = _apply_active_cover_mitigation(target, final_damage)

					# Update the hit amount before passing it to the ResultProcessor
					hit["amount"] = final_damage

					target["last_hit_frame"] = current_battle_frame
					target["last_attacker_index"] = current_attacker
					chain_count_emitted = target["chain_count"]

					var previous_hp = target.get("current_hp", 0)

					# Hand hit receipt and target to result_processor
					result_processor.apply_receipt(hit, target)

					# Enemies can drop limit crystals when hit by player attacks.
					if target_team == "enemy":
						_try_drop_limit_crystal(target_index, attacker_team, hit, final_damage)

					# If this hit killed them, roll for drops!
					if previous_hp > 0 and target["current_hp"] == 0 and target_team == "enemy":
						_roll_enemy_drops(target, target_index)

					if target_team == "enemy":
						set_enemy_hp(target_index, target["current_hp"])
					else:
						# For UI stats, we still need the original party_data index
						# For now, search it by instance_id or let request_unit_stats find it
						var p_idx = target.get("index", -1)
						if p_idx != -1:
							request_unit_stats(p_idx)

			attack_landed.emit(attacker_team, attacker_index, target_team, target_index, final_damage, chain_count_emitted, hit.get("type", ""))
			pending_hits.remove_at(i)

	_check_turn_progression()

func _get_living_player_party_indices() -> Array[int]:
	var living_indices: Array[int] = []
	for i in range(party_data.size()):
		var unit_data: Dictionary = party_data[i]
		if unit_data.is_empty():
			continue
		if int(unit_data.get("current_hp", 0)) > 0:
			living_indices.append(i)
	return living_indices

func _grant_limit_to_unit(unit_index: int, amount: int) -> void:
	if unit_index < 0 or unit_index >= party_data.size():
		return

	var unit_data: Dictionary = party_data[unit_index]
	if unit_data.is_empty():
		return

	var current_limit: int = int(unit_data.get("limit_gauge", 0))
	var max_limit: int = int(unit_data.get("max_limit", 0))
	if max_limit <= 0:
		return

	var next_limit: int = clampi(current_limit + amount, 0, max_limit)
	if next_limit == current_limit:
		return

	unit_data["limit_gauge"] = next_limit
	request_unit_stats(unit_index)

func _try_drop_limit_crystal(enemy_index: int, attacker_team: String, hit: Dictionary, final_damage: int) -> void:
	if attacker_team != "player":
		return
	if final_damage <= 0:
		return
	if str(hit.get("type", "")) != "DAMAGE":
		return
	if enemy_index < 0 or enemy_index >= enemy_units.size():
		return
	if randf() > LIMIT_CRYSTAL_DROP_CHANCE:
		return

	var eligible_units: Array[int] = _get_living_player_party_indices()
	if eligible_units.is_empty():
		return

	var random_target_slot: int = randi() % eligible_units.size()
	var target_unit_index: int = eligible_units[random_target_slot]
	_grant_limit_to_unit(target_unit_index, LIMIT_CRYSTAL_GAIN)
	limit_crystal_dropped.emit(enemy_index, target_unit_index)


func initialize_battle(mission_id: String) -> void:
	
	current_mission_id = mission_id
	var mission_data = DataManager.get_mission_data_local(str(current_mission_id))

	total_waves = mission_data.get("wave_count", 1)
	current_wave = 1
	mission_drops.clear()
	used_items.clear()
	var mission_challenges: Variant = mission_data.get("challenges", [])
	var challenge_count: int = mission_challenges.size() if mission_challenges is Array else 0
	challenge_results.resize(challenge_count)
	challenge_results.fill(false)

	party_data = []

	if DataManager.parties.size() > 0:
		var active_party: Dictionary = DataManager.get_active_party()
		var party_instance_ids: Array = []
		if not active_party.is_empty():
			party_instance_ids = active_party.get("units", [])
		else:
			var fallback_party: Variant = DataManager.parties[0]
			if typeof(fallback_party) == TYPE_DICTIONARY:
				party_instance_ids = fallback_party.get("units", [])
			elif typeof(fallback_party) == TYPE_ARRAY:
				party_instance_ids = fallback_party

		for instance_id in party_instance_ids:
			if instance_id == "":
				party_data.append({})
				continue

			var owned_unit = null
			for u in DataManager.owned_units_ids:
				if typeof(u) == TYPE_DICTIONARY and u.get("instance_id") == instance_id:
					owned_unit = u
					break

			if owned_unit != null:
				var battle_unit = owned_unit.duplicate()

				# Use StatCalculator to get accurate max HP and MP
				var final_stats = battle_unit.get("final_stats", {})
				
				battle_unit["final_stats"] = StatCalculator.calculate_final_stats(battle_unit)
				final_stats = StatCalculator.calculate_final_stats(battle_unit)
					
				final_stats = final_stats["stats"]
				
				var max_hp = final_stats.get("HP", 100)
				var max_mp = final_stats.get("MP", 10)

				battle_unit["max_hp"] = max_hp
				battle_unit["current_hp"] = max_hp
				battle_unit["max_mp"] = max_mp
				battle_unit["current_mp"] = max_mp
				var limitburst_id: String = str(battle_unit.get("limitburst_id", ""))
				battle_unit["limitburst_id"] = limitburst_id
				var max_limit_gauge: int = DataManager.get_limitburst_max_gauge(limitburst_id)
				battle_unit["limit_gauge"] = 0
				battle_unit["max_limit"] = max_limit_gauge
				battle_unit["queued_action"] = CombatAction.ATTACK
				battle_unit["queued_action_name"] = ""
				battle_unit["queued_action_id"] = ""
				battle_unit["is_defending"] = false

				battle_unit["chain_count"] = 0
				battle_unit["last_hit_frame"] = -100
				battle_unit["last_attacker_index"] = -1

				battle_unit["team"] = "player"
				battle_unit["index"] = party_data.size()

				party_data.append(battle_unit)
			else:
				party_data.append({})

	player_units.clear()
	for unit in party_data:
		if not unit.is_empty():
			player_units.append(unit)

	# Load enemy data
	var dungeon_id = str(int(mission_data.get("dungeon_id", "")))
	var dungeon_data = DataManager.game_data_dungeons.get(str(dungeon_id), {})
	_spawn_enemies_for_wave(mission_data, dungeon_data)

	current_state = BattleState.PLAYER_TURN
	player_units_acted_this_turn.clear()
	current_battle_frame = 0
	pending_hits.clear()

	turn_count = 1
	is_transitioning = false
	battle_state_ready.emit()

func set_challenge_result(challenge_index: int, value: bool) -> void:
	if challenge_index < 0 or challenge_index >= challenge_results.size():
		push_error("BattleManager: set_challenge_result index %d out of range (size %d)" % [challenge_index, challenge_results.size()])
		return
	challenge_results[challenge_index] = value

func set_enemy_hp(enemy_index: int, new_hp: int) -> void:
	if enemy_index < 0 or enemy_index >= enemy_units.size():
		return

	var enemy = enemy_units[enemy_index]
	enemy["current_hp"] = new_hp
	var max_hp = enemy.get("max_hp", enemy.get("hp", 1000))
	var pct: int = 0
	if max_hp > 0:
		pct = int((float(enemy["current_hp"]) / float(max_hp)) * 100.0)
	enemy_hp_changed.emit(enemy_index, enemy["current_hp"], max_hp, pct)

func set_queued_action(unit_index: int, new_action: CombatAction, action_name: String = "", action_id: String = "", payload: Dictionary = {}) -> void:
	if unit_index < 0 or unit_index >= party_data.size():
		return
	var unit_data: Dictionary = party_data[unit_index]
	if unit_data.is_empty():
		return
		
	var old_payload = unit_data.get("queued_payload", {})
	if old_payload.get("is_item", false) == true:
		item_refunded.emit(old_payload.get("original_item_id"))
		
	unit_data["queued_action"] = new_action
	unit_data["queued_action_name"] = action_name
	unit_data["queued_action_id"] = action_id
	unit_data["queued_payload"] = payload

	action_queued.emit(unit_index, new_action, action_id)

func _resolve_queued_action_data(action_id: String, payload: Dictionary) -> Dictionary:
	var resolved_action_data: Dictionary = payload.get("resolved_action_data", {})
	if not resolved_action_data.is_empty():
		return {
			"resolved_action_id": str(payload.get("resolved_action_id", action_id)),
			"resolved_action_data": resolved_action_data,
			"parsed_data": payload.get("parsed_data", {})
		}

	var resolved_action_id: String = str(payload.get("resolved_action_id", action_id))
	return DataManager.resolve_combat_skill(resolved_action_id)

func _extract_skill_mp_cost(skill_data: Dictionary) -> int:
	var cost_value: Variant = skill_data.get("cost", {})
	if cost_value is Dictionary:
		var cost_dict: Dictionary = cost_value
		if cost_dict.has("MP"):
			return maxi(0, int(cost_dict.get("MP", 0)))
	return 0

func _try_spend_skill_mp(unit_index: int, unit_data: Dictionary, payload_data: Dictionary, skill_data: Dictionary) -> bool:
	if unit_data.is_empty():
		return false

	var source_type: String = str(payload_data.get("source_type", "skill"))
	if source_type == "limitburst":
		return true

	var mp_cost: int = _extract_skill_mp_cost(skill_data)
	if mp_cost <= 0:
		return true

	var current_mp: int = int(unit_data.get("current_mp", 0))
	if current_mp < mp_cost:
		return false

	unit_data["current_mp"] = maxi(0, current_mp - mp_cost)
	request_unit_stats(unit_index)
	return true

func execute_queued_action(attacker_index: int) -> void:
	if current_state != BattleState.PLAYER_TURN:
		return
	if attacker_index in player_units_acted_this_turn:
		return

	player_units_acted_this_turn.append(attacker_index)
	var attacker_data: Dictionary = party_data[attacker_index] if attacker_index < party_data.size() else {}
	if attacker_data.is_empty(): return
	var action: int = attacker_data.get("queued_action", CombatAction.ATTACK)
	
	unit_acted.emit(attacker_index)

	if action == CombatAction.DEFEND:
		attacker_data["is_defending"] = true
		_check_turn_progression()
		return
	elif action == CombatAction.SKILL or action == CombatAction.ITEM:
		var action_name: String = attacker_data.get("queued_action_name", "")
		var action_id: String = attacker_data.get("queued_action_id", "")
		var payload_data: Dictionary = attacker_data.get("queued_payload", {})
		print("Executing: ", action_name)

		unit_action_started.emit(attacker_index, action)

		if action == CombatAction.ITEM:
			var item_id: String = payload_data.get("original_item_id", "")
			if item_id != "":
				used_items[item_id] = used_items.get(item_id, 0) + 1

		var resolved_action: Dictionary = _resolve_queued_action_data(action_id, payload_data)
		var target_skill_data: Dictionary = resolved_action.get("resolved_action_data", {}) if not resolved_action.is_empty() else {}

		if target_skill_data.is_empty():
			push_error("Error: Skill/Item Ability not found in database: " + action_name)
			return

		if action == CombatAction.SKILL:
			if not _try_spend_skill_mp(attacker_index, attacker_data, payload_data, target_skill_data):
				print("BattleManager: Not enough MP to execute skill: ", action_name)
				_check_turn_progression()
				return

		var parsed_data: Dictionary = payload_data.get("parsed_data", {})
		if parsed_data.is_empty():
			parsed_data = resolved_action.get("parsed_data", {}) if not resolved_action.is_empty() else {}
		if parsed_data.is_empty():
			parsed_data = DataManager.parse_skill_effects(target_skill_data)
		print("Parsed Skill/Item: ", parsed_data)

		# queued_target_index is always a party_data index (stable slot reference)
		var target_team: String = attacker_data.get("queued_target_team", "enemy")
		var target_idx: int = attacker_data.get("queued_target_index", 0)

		var primary_target: Dictionary = {}
		if target_team == "enemy":
			if target_idx < 0 or target_idx >= enemy_units.size(): target_idx = 0
			if enemy_units.size() > 0: primary_target = enemy_units[target_idx]
		else:
			# Ally targets store party_data indices; player_units is a compact subset whose positions differ when slots are empty
			if target_idx < 0 or target_idx >= party_data.size(): target_idx = 0
			if party_data.size() > 0: primary_target = party_data[target_idx]

		# Route the skill to the execution pipeline
		execute_parsed_skill(parsed_data, attacker_data, primary_target)

		_check_turn_progression()
		return
	elif action == CombatAction.ATTACK:
		# Keep accepting inputs for other units by not changing state here
		unit_action_started.emit(attacker_index, CombatAction.ATTACK)
		
		# Build a dummy effect so it goes through our standard pipeline
		var dummy_effect = {
			"type": "PHYSICAL_DAMAGE",
			"modifier": 1.0,
			"target_area": 1,
			"target_type": 1
		}
		
		# Retrieve the actual queued target index
		var target_index: int = attacker_data.get("queued_target_index", 0)
		var target_team: String = attacker_data.get("queued_target_team", "enemy")
		
		var attack_frames = attacker_data.get("attack_frames", [30])
		var attack_damage = attacker_data.get("attack_damage", [[100]])
		
		var target_data: Dictionary = {}
		if target_team == "enemy":
			if target_index < 0 or target_index >= enemy_units.size(): target_index = 0
			if enemy_units.size() > 0: target_data = enemy_units[target_index]
		else:
			# Ally targets store party_data indices; player_units is a compact subset whose positions differ when slots are empty
			if target_index < 0 or target_index >= party_data.size(): target_index = 0
			if party_data.size() > 0: target_data = party_data[target_index]

		# Insert attack frames/damage directly into the dummy effect so standard processing can read them
		dummy_effect["attack_frames"] = attack_frames
		dummy_effect["attack_damage"] = attack_damage
		_queue_effect_hits(dummy_effect, attacker_data, target_data)

func _check_turn_progression() -> void:
	if not pending_hits.is_empty():
		return

	check_battle_state()

	if current_state == BattleState.PLAYER_TURN:
		var all_acted: bool = true

		for i in range(player_units.size()):
			var unit: Dictionary = player_units[i]
			# A living unit is not empty, has current_hp, and current_hp > 0
			if not unit.is_empty() and unit.has("current_hp") and unit.get("current_hp") > 0:
				# Find the original party index since player_units_acted_this_turn tracks UI party indices
				var p_idx = unit.get("index", -1)
				if p_idx != -1 and p_idx not in player_units_acted_this_turn:
					all_acted = false
					break

		if all_acted:
			current_state = BattleState.ENEMY_TURN
			_execute_enemy_turn()
	elif current_state == BattleState.ENEMY_TURN:
		_on_turn_end("enemy")
		_tick_active_effect_durations(party_data)
		_tick_active_effect_durations(enemy_units)
		# Transition back to PLAYER_TURN
		player_units_acted_this_turn.clear()
		for unit in player_units:
			if not unit.is_empty():
				unit["is_defending"] = false
				unit.erase("queued_payload")
				# Reset target so stale per-skill targets (e.g. self-targeting) don't bleed into next turn's basic attack
				unit["queued_target_team"] = "enemy"
				unit["queued_target_index"] = 0
				
		turn_count += 1
		turn_changed.emit(turn_count)
		current_state = BattleState.PLAYER_TURN

func _tick_active_effect_durations(units: Array) -> void:
	for unit in units:
		if unit.is_empty():
			continue
		if not unit.has("active_effects"):
			continue

		var active_effects: Array = unit.get("active_effects", [])
		if active_effects.is_empty():
			continue

		var remaining_effects: Array = []
		for effect in active_effects:
			if typeof(effect) != TYPE_DICTIONARY:
				continue

			var next_duration: int = int(effect.get("duration", 0)) - 1
			if next_duration > 0:
				var updated_effect: Dictionary = effect.duplicate(true)
				updated_effect["duration"] = next_duration
				remaining_effects.append(updated_effect)

		unit["active_effects"] = remaining_effects
		unit["final_stats"] = StatCalculator.calculate_final_stats(unit)

func _execute_enemy_turn() -> void:
	var living_player_indices: Array[int] = []
	for i in range(player_units.size()):
		var unit: Dictionary = player_units[i]
		if not unit.is_empty() and unit.has("current_hp") and unit.get("current_hp") > 0:
			living_player_indices.append(i)

	if living_player_indices.size() > 0:
		var random_idx: int = randi() % living_player_indices.size()
		var target_index: int = living_player_indices[random_idx]
		var target_unit: Dictionary = {}
		if target_index >= 0 and target_index < player_units.size():
			target_unit = player_units[target_index]

		# Let's assume enemy index 0 for now
		var attacker_index: int = 0
		
		# Emit signal so the UI can play the attack animation
		enemy_action_started.emit(attacker_index, CombatAction.ATTACK)

		var dummy_effect = {
			"type": "PHYSICAL_DAMAGE",
			"modifier": 1.0,
			"target_area": 1,
			"target_type": 1
		}
		
		# Calculate dynamic attack frames based on enemy's animation duration (looping twice)
		var monster_id: String = str(enemy_units[attacker_index].get("id", "5010010"))
		var anim_data = TextureBuilder.load_monster_animation_data(monster_id, "atk")
		
		var attack_delay_frames = ENEMY_ATTACK_DELAY_FRAMES
		if not anim_data.is_empty():
			var delays = anim_data.get("delays", [])
			var total_frames: int = 0
			for d in delays:
				# delays in JSON are typically frame counts at 60fps
				# combat_sprite uses float(d)/60.0 for seconds.
				# We want total frames to wait.
				total_frames += int(d)
			if total_frames > 0:
				attack_delay_frames = total_frames * 2 # Play animation twice

		var attack_frames = [attack_delay_frames]
		var attack_damage = [[100]]
		
		var caster_data = enemy_units[attacker_index]

		# Insert attack frames/damage directly into the dummy effect so standard processing can read them
		dummy_effect["attack_frames"] = attack_frames
		dummy_effect["attack_damage"] = attack_damage
		_queue_effect_hits(dummy_effect, caster_data, target_unit)

func request_unit_stats(index: int) -> void:
	if index < 0 or index >= party_data.size():
		return

	var unit_data: Dictionary = party_data[index]
	if unit_data.is_empty():
		return

	var unit_name: String = unit_data.get("name", "ERR_MISSING_NAME")
	var cur_hp: int = unit_data.get("current_hp", 0)
	var max_hp: int = unit_data.get("max_hp", 1)
	var cur_mp: int = unit_data.get("current_mp", 0)
	var max_mp: int = unit_data.get("max_mp", 1)
	var cur_limit: int = unit_data.get("limit_gauge", 0)
	var max_limit: int = unit_data.get("max_limit", 100)

	unit_stats_updated.emit(index, unit_name, cur_hp, max_hp, cur_mp, max_mp, cur_limit, max_limit)


func _are_all_units_dead(team: Array) -> bool:
	if team.size() == 0:
		return true # Prevent edge cases where an empty wave triggers a soft-lock

	for unit in team:
		if unit.get("current_hp", 0) > 0:
			return false

	return true

func check_battle_state() -> void:
	# If we are already handling a win/loss, ignore further checks
	if is_transitioning:
		return

	# Check for Game Over first
	if _are_all_units_dead(player_units):
		is_transitioning = true
		_trigger_defeat()
		return

	# Check for Wave Clear
	if _are_all_units_dead(enemy_units):
		is_transitioning = true
		_trigger_wave_clear()
		return

	# Battle continues
	# print("BattleManager: Both sides still standing.")

func _trigger_defeat() -> void:
	print("BattleManager: Defeat! All allies have fallen.")
	if DataManager.has_method("request_finish_mission"):
		await DataManager.request_finish_mission(false, current_mission_id, used_items)
	mission_failed.emit()

func _trigger_wave_clear() -> void:
	print("BattleManager: Wave %d cleared!" % current_wave)

	# 1. Wait for the death tweens to finish (0.5 to 1.0 seconds)
	await get_tree().create_timer(1.0).timeout

	if current_wave >= total_waves:
		_trigger_mission_complete()
	else:
		# 2. Tell the UI to do the rolling number animation
		wave_transition_started.emit(current_wave, current_wave + 1, total_waves)

		# 3. Wait for the UI animation to finish before actually spawning
		await get_tree().create_timer(2.0).timeout

		_spawn_next_wave()

func _trigger_mission_complete() -> void:
	print("BattleManager: Final wave cleared. Initiating mission rewards...")
	print("Mission Drops: ", mission_drops)

	if DataManager.has_method("request_finish_mission"):
		await DataManager.request_finish_mission(true, current_mission_id, used_items, challenge_results, mission_drops)

	mission_cleared.emit()

func _spawn_next_wave() -> void:
	current_wave += 1
	print("BattleManager: Spawning Wave %d..." % current_wave)

	var mission_data = DataManager.get_mission_data_local(str(current_mission_id))
	var dungeon_id = str(int(mission_data.get("dungeon_id", "")))
	var dungeon_data = DataManager.game_data_dungeons.get(str(dungeon_id), {})

	_spawn_enemies_for_wave(mission_data, dungeon_data)

	wave_changed.emit(current_wave, total_waves)

	current_state = BattleState.PLAYER_TURN
	player_units_acted_this_turn.clear()
	current_battle_frame = 0
	pending_hits.clear()

	battle_state_ready.emit()

	# Only unlock after everything is fully set up
	is_transitioning = false

func _generate_enemy_data(dungeon_monster_data: Dictionary) -> Dictionary:
	var global_monster_data = {}
	var monster_name = dungeon_monster_data.get("name", "")

	if monster_name != "":
		for monster in DataManager.game_data_monsters:
			if typeof(monster) == TYPE_DICTIONARY and str(monster.get("name", "")) == str(monster_name):
				global_monster_data = monster.duplicate(true)
				break

	var enemy_data = global_monster_data.duplicate(true)
	for key in dungeon_monster_data:
		enemy_data[key] = dungeon_monster_data[key]

	var enemy_max_hp = int(enemy_data.get("hp", 1000))
	enemy_data["max_hp"] = enemy_max_hp
	enemy_data["current_hp"] = enemy_max_hp

	# Tracking variables
	enemy_data["chain_count"] = 0
	enemy_data["last_hit_frame"] = -100
	enemy_data["last_attacker_index"] = -1

	return enemy_data

func _roll_enemy_drops(enemy_data: Dictionary, enemy_index: int) -> void:
	var loot_table = enemy_data.get("loot", {})
	var drops = loot_table.get("drops", [])

	if drops.is_empty():
		return

	# 1. Global chance to drop absolutely nothing (e.g., 50% fail rate)
	if randf() > 0.50:
		return # No chest dropped!

	# 2. If we passed the global check, pick ONE random item from the pool
	var random_item_idx = randi() % drops.size()
	var selected_item_id = str(drops[random_item_idx])

	# 3. Add to escrow and emit
	mission_drops.append(selected_item_id)
	item_dropped.emit(enemy_index, selected_item_id)


func _build_monster_spawn_pool(mission_data: Dictionary, dungeon_data: Dictionary) -> Array:
	var mission_monsters: Variant = mission_data.get("monsters", [])
	var dungeon_monsters: Variant = dungeon_data.get("monsters", [])

	var mission_pool: Array = []
	var dungeon_by_name: Dictionary = {}
	if dungeon_monsters is Array:
		for dungeon_monster in dungeon_monsters:
			if dungeon_monster is Dictionary:
				var monster_name: String = str((dungeon_monster as Dictionary).get("name", ""))
				if monster_name != "":
					dungeon_by_name[monster_name] = (dungeon_monster as Dictionary)

	if mission_monsters is Array and mission_monsters.size() > 0:
		for mission_monster in mission_monsters:
			if mission_monster is Dictionary:
				mission_pool.append((mission_monster as Dictionary).duplicate(true))
			elif mission_monster is String:
				var mission_monster_name: String = str(mission_monster)
				if dungeon_by_name.has(mission_monster_name):
					mission_pool.append((dungeon_by_name[mission_monster_name] as Dictionary).duplicate(true))
				else:
					mission_pool.append({"name": mission_monster_name})

	if mission_pool.size() > 0:
		return mission_pool

	if dungeon_monsters is Array:
		return dungeon_monsters

	return []

func _spawn_enemies_for_wave(mission_data: Dictionary, dungeon_data: Dictionary) -> void:
	enemy_units.clear()
	var monsters_in_dungeon: Array = _build_monster_spawn_pool(mission_data, dungeon_data)

	if monsters_in_dungeon.size() > 0:
		var spawn_count = randi() % 3 + 1 # Random number between 1 and 3

		for i in range(spawn_count):
			var random_monster_idx = randi() % monsters_in_dungeon.size()
			var selected_monster_data = monsters_in_dungeon[random_monster_idx]

			var fully_hydrated_enemy = _generate_enemy_data(selected_monster_data)

			fully_hydrated_enemy["team"] = "enemy"
			fully_hydrated_enemy["index"] = enemy_units.size()
			enemy_units.append(fully_hydrated_enemy)


# Helper function to grab only living units
static func _get_living_units(team_array: Array) -> Array[Dictionary]:
	var living: Array[Dictionary] = []
	for unit in team_array:
		if not unit.is_empty() and unit.get("current_hp", 0) > 0:
			living.append(unit)
	return living

func _resolve_targets(target_area: int, target_type: int, caster: Dictionary, primary_target: Dictionary) -> Array[Dictionary]:
	var is_player_caster: bool = caster.get("team", "") == "player"
	# Pools are relative to the caster: enemy_pool is the opposing team, ally_pool is the caster's own team.
	# For player casters, allies are all party_data slots (stable indices, includes empty/dead slots).
	var enemy_pool: Array = enemy_units if is_player_caster else player_units
	var ally_pool: Array = party_data if is_player_caster else enemy_units

	# TYPE 3: SELF
	if target_type == 3:
		return [caster]

	# TYPE 1: ENEMY (opposing team) - never target dead enemies
	if target_type == 1:
		var living_enemies: Array[Dictionary] = _get_living_units(enemy_pool)
		if living_enemies.is_empty(): return [] # Win condition safety

		if target_area == 2: # AOE
			return living_enemies
		else: # Single Target
			if primary_target.get("current_hp", 0) > 0:
				return [primary_target]
			else:
				return [living_enemies[0]] # Fallback to first alive if target died

	# TYPE 2: ALLY (own team)
	if target_type in [2, 6]:
		if target_area == 2: # AOE - living allies only
			var living_allies: Array[Dictionary] = _get_living_units(ally_pool)
			if living_allies.is_empty(): return []
			return living_allies
		else: # Single Target - dead allies are valid targets (e.g. revive)
			if not primary_target.is_empty():
				return [primary_target]
			else:
				return [caster]

	# Fallback catch-all
	return []

func _queue_effect_hits(effect: Dictionary, caster: Dictionary, primary_target: Dictionary) -> void:
	var actual_targets: Array[Dictionary] = _resolve_targets(
		effect.get("target_area", 1),
		effect.get("target_type", 1),
		caster,
		primary_target
	)

	if effect.get("target_type", 1) == 1:
		actual_targets = _evaluate_cover_interception(actual_targets, effect, _get_defending_pool(caster))

	var hit_payloads: Array[Dictionary] = action_processor.execute_parsed_effect(effect, caster, actual_targets)
	for hit in hit_payloads:
		hit["frame_to_execute"] += current_battle_frame
		hit["execute_on_frame"] = hit["frame_to_execute"]
		hit.erase("frame_to_execute")
		pending_hits.append(hit)

func _get_defending_pool(caster: Dictionary) -> Array:
	var caster_team: String = str(caster.get("team", "")).to_lower()
	return player_units if caster_team == "enemy" else enemy_units

func _is_cover_interceptable_effect(effect: Dictionary) -> bool:
	var effect_type: String = str(effect.get("type", "")).to_lower()
	return effect_type in ["physical_damage", "magic_damage"]

func _ensure_transient_turn_state(unit: Dictionary) -> Dictionary:
	var transient: Dictionary = unit.get("transient_turn_state", {})
	if transient.is_empty():
		transient = {}
		unit["transient_turn_state"] = transient
	return transient

func _find_active_aoe_coverer(defending_pool: Array) -> Dictionary:
	for unit_data in defending_pool:
		var unit: Dictionary = unit_data
		if unit.is_empty() or int(unit.get("current_hp", 0)) <= 0:
			continue
		var transient: Dictionary = unit.get("transient_turn_state", {})
		if bool(transient.get(COVER_STATE_AOE, false)):
			return unit
	return {}

func _cover_supports_effect_type(cover_effect: Dictionary, incoming_effect_type: String) -> bool:
	var effect_type: String = incoming_effect_type.to_lower()
	if effect_type not in ["physical_damage", "magic_damage"]:
		return false

	var params: Dictionary = cover_effect.get("params", {})
	var phys_mag_mode = params.get("phys_mag", "both")

	if typeof(phys_mag_mode) == TYPE_STRING:
		var mode_text: String = str(phys_mag_mode).to_lower()
		if mode_text in ["physical", "phys"]:
			return effect_type == "physical_damage"
		if mode_text in ["magic", "mag"]:
			return effect_type == "magic_damage"
		return true

	if typeof(phys_mag_mode) in [TYPE_INT, TYPE_FLOAT]:
		var mode_id: int = int(phys_mag_mode)
		if mode_id == 1:
			return effect_type == "physical_damage"
		if mode_id == 2:
			return effect_type == "magic_damage"

	return true

func _get_best_aoe_cover_effect(defender: Dictionary, incoming_effect_type: String) -> Dictionary:
	var best_effect: Dictionary = {}
	var best_chance: float = -1.0

	for active_effect_data in defender.get("active_effects", []):
		var active_effect: Dictionary = active_effect_data
		if str(active_effect.get("type", "")).to_lower() != "aoe_cover":
			continue
		if not _cover_supports_effect_type(active_effect, incoming_effect_type):
			continue

		var chance: float = clampf(float(active_effect.get("params", {}).get("pct_chance", 0.0)), 0.0, 100.0)
		if chance > best_chance:
			best_chance = chance
			best_effect = active_effect

	return best_effect

func _is_unit_currently_st_covered(unit: Dictionary, defending_pool: Array) -> bool:
	var unit_identity: String = str(unit.get("identity", ""))
	if unit_identity == "":
		return false

	for other_data in defending_pool:
		var other: Dictionary = other_data
		if other == unit:
			continue
		if other.is_empty() or int(other.get("current_hp", 0)) <= 0:
			continue
		var transient: Dictionary = other.get("transient_turn_state", {})
		if str(transient.get(COVER_STATE_ST, "")) == unit_identity:
			return true

	return false

func _flag_cover_mitigation(defender: Dictionary, cover_effect: Dictionary) -> void:
	var transient: Dictionary = _ensure_transient_turn_state(defender)
	var params: Dictionary = cover_effect.get("params", {})

	var mitigation_min: int = int(params.get("dmg_reduce_min", 0))
	var mitigation_max: int = int(params.get("dmg_reduce_max", mitigation_min))

	if mitigation_max < mitigation_min:
		var swap_value: int = mitigation_min
		mitigation_min = mitigation_max
		mitigation_max = swap_value

	mitigation_min = clampi(mitigation_min, 0, 100)
	mitigation_max = clampi(mitigation_max, 0, 100)

	var rolled_mitigation: int = mitigation_min
	if mitigation_max > mitigation_min:
		rolled_mitigation = (randi() % ((mitigation_max - mitigation_min) + 1)) + mitigation_min

	transient[COVER_STATE_MITIGATION] = rolled_mitigation
	defender["transient_turn_state"] = transient

func _apply_active_cover_mitigation(target: Dictionary, incoming_damage: int) -> int:
	if incoming_damage <= 0:
		return incoming_damage

	var transient: Dictionary = target.get("transient_turn_state", {})
	if transient.is_empty() or not transient.has(COVER_STATE_MITIGATION):
		return incoming_damage

	var mitigation_pct: int = clampi(int(transient.get(COVER_STATE_MITIGATION, 0)), 0, 100)
	var mitigated_damage: int = int(round(float(incoming_damage) * (100.0 - float(mitigation_pct)) / 100.0))
	return maxi(0, mitigated_damage)

func _evaluate_cover_interception(intended_targets: Array[Dictionary], effect: Dictionary, defending_pool: Array) -> Array[Dictionary]:
	if intended_targets.is_empty():
		return intended_targets
	if not _is_cover_interceptable_effect(effect):
		return intended_targets

	var active_aoe_coverer: Dictionary = _find_active_aoe_coverer(defending_pool)
	if not active_aoe_coverer.is_empty():
		var already_covered_targets: Array[Dictionary] = []
		for i in range(intended_targets.size()):
			already_covered_targets.append(active_aoe_coverer)
		return already_covered_targets

	var incoming_effect_type: String = str(effect.get("type", "")).to_lower()

	for defender_data in defending_pool:
		var defender: Dictionary = defender_data
		if defender.is_empty() or int(defender.get("current_hp", 0)) <= 0:
			continue
		if _is_unit_currently_st_covered(defender, defending_pool):
			continue

		var cover_effect: Dictionary = _get_best_aoe_cover_effect(defender, incoming_effect_type)
		if cover_effect.is_empty():
			continue

		var allies_in_danger: int = 0
		for target in intended_targets:
			if target != defender:
				allies_in_danger += 1

		if allies_in_danger <= 0:
			continue

		var chance: float = clampf(float(cover_effect.get("params", {}).get("pct_chance", 0.0)), 0.0, 100.0)
		if chance <= 0.0:
			continue

		var procced: bool = false
		for i in range(allies_in_danger):
			if randf() * 100.0 < chance:
				procced = true
				break

		if not procced:
			continue

		var transient: Dictionary = _ensure_transient_turn_state(defender)
		transient[COVER_STATE_AOE] = true
		defender["transient_turn_state"] = transient
		_flag_cover_mitigation(defender, cover_effect)

		var covered_targets: Array[Dictionary] = []
		for i in range(intended_targets.size()):
			covered_targets.append(defender)
		return covered_targets

	return intended_targets

func _clear_cover_transient_state(defending_pool: Array) -> void:
	for unit_data in defending_pool:
		var unit: Dictionary = unit_data
		if unit.is_empty():
			continue
		var transient: Dictionary = unit.get("transient_turn_state", {})
		if transient.is_empty():
			continue

		transient.erase(COVER_STATE_AOE)
		transient.erase(COVER_STATE_ST)
		transient.erase(COVER_STATE_MITIGATION)

		if transient.is_empty():
			unit.erase("transient_turn_state")
		else:
			unit["transient_turn_state"] = transient

func _on_turn_end(active_team: String) -> void:
	var defending_pool: Array = player_units if active_team.to_lower() == "enemy" else enemy_units
	_clear_cover_transient_state(defending_pool)

func execute_parsed_skill(parsed_skill: Dictionary, caster: Dictionary, primary_target: Dictionary) -> void:
	var effects = parsed_skill.get("effects", [])

	for i in range(effects.size()):
		var effect = effects[i]
		_queue_effect_hits(effect, caster, primary_target)
