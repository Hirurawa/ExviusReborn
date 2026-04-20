extends Node

signal battle_state_ready
signal enemy_hp_changed(enemy_index: int, new_hp: int, max_hp: int, hp_percent: int)
signal turn_changed(new_turn: int)
signal unit_stats_updated(index: int, unit_name: String, cur_hp: int, max_hp: int, cur_mp: int, max_mp: int, cur_limit: int, max_limit: int)
signal attack_landed(attacker_team: String, attacker_index: int, target_team: String, target_index: int, damage: int, chain_count: int)
signal unit_acted(index: int)
signal unit_action_started(unit_index: int, action: CombatAction)
signal enemy_action_started(enemy_index: int, action: CombatAction)
signal mission_cleared
signal mission_failed
signal wave_changed(current_wave: int, total_waves: int)
signal wave_transition_started(current_wave: int, next_wave: int, total_waves: int)
signal item_dropped(enemy_index: int, item_id: String)

enum BattleState { INIT, PLAYER_TURN, RESOLVING_TURN, ENEMY_TURN, BATTLE_OVER }
enum CombatAction { ATTACK, DEFEND, SKILL, ITEM }

const ENEMY_ATTACK_DELAY_FRAMES: int = 60

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

func _ready() -> void:
	# 1. Instantiate the script purely in code
	action_processor = preload("res://features/battle/logic/ActionProcessor.gd").new()
	result_processor = preload("res://features/battle/logic/result_processor.gd").new()
	
	# 2. Give it a name so it shows up cleanly in the debugger
	action_processor.name = "ActionProcessor"
	result_processor.name = "ResultProcessor"
	
	# 3. Add it as a child to the BattleManager
	add_child(action_processor)
	add_child(result_processor)
	#pass

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

					# Update the hit amount before passing it to the ResultProcessor
					hit["amount"] = final_damage

					target["last_hit_frame"] = current_battle_frame
					target["last_attacker_index"] = current_attacker
					chain_count_emitted = target["chain_count"]

					var previous_hp = target.get("current_hp", 0)

					# Hand hit receipt and target to result_processor
					result_processor.apply_receipt(hit, target)

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

			attack_landed.emit(attacker_team, attacker_index, target_team, target_index, final_damage, chain_count_emitted)
			pending_hits.remove_at(i)

	_check_turn_progression()


func initialize_battle(mission_id: String) -> void:
	
	current_mission_id = mission_id
	var mission_data = DataManager.game_data_missions.get(str(current_mission_id), {})

	total_waves = mission_data.get("wave_count", 1)
	current_wave = 1
	mission_drops.clear()

	party_data = []

	if DataManager.parties.size() > 0:
		var first_party = DataManager.parties[0]
		var party_instance_ids = []
		if typeof(first_party) == TYPE_DICTIONARY:
			party_instance_ids = first_party.get("units", [])
		elif typeof(first_party) == TYPE_ARRAY:
			party_instance_ids = first_party

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
				battle_unit["limit_gauge"] = 0
				battle_unit["max_limit"] = 100 # arbitrary placeholder
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
	_spawn_enemies_for_wave(dungeon_data)

	current_state = BattleState.PLAYER_TURN
	player_units_acted_this_turn.clear()
	current_battle_frame = 0
	pending_hits.clear()

	turn_count = 1
	is_transitioning = false
	battle_state_ready.emit()

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

func set_queued_action(unit_index: int, new_action: CombatAction, action_name: String = "", action_id: String = "") -> void:
	if unit_index < 0 or unit_index >= party_data.size():
		return
	var unit_data: Dictionary = party_data[unit_index]
	if unit_data.is_empty():
		return
	unit_data["queued_action"] = new_action
	unit_data["queued_action_name"] = action_name
	unit_data["queued_action_id"] = action_id

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
		print("Executing: ", action_name)

		if action == CombatAction.SKILL:
			var target_skill_data: Dictionary = DataManager.game_data_skills_magic.get(action_id, {})
			if target_skill_data == {}:
				target_skill_data = DataManager.game_data_skills_ability.get(action_id, {})

			if target_skill_data.is_empty():
				push_error("Error: Skill not found in database: " + action_name)
				return

			#var parsed_data: Dictionary = OpcodeParser.parse_skill(target_skill_data)
			var parsed_data: Dictionary = OpcodeParser.parse_skill_improved(target_skill_data)
			print("Parsed Skill: ", parsed_data)

			# Attempt to get targeting data from the queue, fallback to enemy 0 for now
			var target_team: String = attacker_data.get("queued_target_team", "enemy")
			var target_idx: int = attacker_data.get("queued_target_index", 0)

			var primary_target: Dictionary = {}
			if target_team == "enemy":
				if target_idx < 0 or target_idx >= enemy_units.size(): target_idx = 0
				if enemy_units.size() > 0: primary_target = enemy_units[target_idx]
			else:
				if target_idx < 0 or target_idx >= player_units.size(): target_idx = 0
				if player_units.size() > 0: primary_target = player_units[target_idx]

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
		var target_index = attacker_data.get("queued_target_index", 0)
		var target_team = attacker_data.get("queued_target_team", "enemy")
		
		var attack_frames = attacker_data.get("attack_frames", [30])
		var attack_damage = attacker_data.get("attack_damage", [[100]])
		
		var target_data: Dictionary = {}
		if target_team == "enemy":
			if target_index < 0 or target_index >= enemy_units.size(): target_index = 0
			if enemy_units.size() > 0: target_data = enemy_units[target_index]
		else:
			if target_index < 0 or target_index >= player_units.size(): target_index = 0
			if player_units.size() > 0: target_data = player_units[target_index]

		# Insert attack frames/damage directly into the dummy effect so standard processing can read them
		dummy_effect["attack_frames"] = attack_frames
		dummy_effect["attack_damage"] = attack_damage

		var hit_payloads = action_processor.execute_parsed_effect(dummy_effect, attacker_data, [target_data])
		for hit in hit_payloads:
			hit["frame_to_execute"] += current_battle_frame
			hit["execute_on_frame"] = hit["frame_to_execute"]
			hit.erase("frame_to_execute")
			pending_hits.append(hit)

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
		# Transition back to PLAYER_TURN
		player_units_acted_this_turn.clear()
		for unit in player_units:
			if not unit.is_empty():
				unit["is_defending"] = false
				
		turn_count += 1
		turn_changed.emit(turn_count)
		current_state = BattleState.PLAYER_TURN

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

		var hit_payloads = action_processor.execute_parsed_effect(dummy_effect, caster_data, [target_unit])
		for hit in hit_payloads:
			hit["frame_to_execute"] += current_battle_frame
			hit["execute_on_frame"] = hit["frame_to_execute"]
			hit.erase("frame_to_execute")
			pending_hits.append(hit)

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
	if DataManager.server_connection:
		await DataManager.server_connection.finish_mission_async(false)
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

	if DataManager.server_connection:
		await DataManager.server_connection.finish_mission_async(true)

	mission_cleared.emit()

func _spawn_next_wave() -> void:
	current_wave += 1
	print("BattleManager: Spawning Wave %d..." % current_wave)

	var mission_data = DataManager.game_data_missions.get(str(current_mission_id), {})
	var dungeon_id = str(int(mission_data.get("dungeon_id", "")))
	var dungeon_data = DataManager.game_data_dungeons.get(str(dungeon_id), {})

	_spawn_enemies_for_wave(dungeon_data)

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


func _spawn_enemies_for_wave(dungeon_data: Dictionary) -> void:
	enemy_units.clear()
	var monsters_in_dungeon = dungeon_data.get("monsters", [])

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
	var targets: Array[Dictionary] = []
	var enemy_pool = enemy_units
	var ally_pool = player_units if caster.get("team") == "player" else enemy_units # Adjust if enemies cast buffs on themselves
	
	# TYPE 3: SELF
	if target_type == 3:
		return [caster]
	
	# TYPE 1: ENEMY
	if target_type == 1:
		var living_enemies = _get_living_units(enemy_pool)
		if living_enemies.is_empty(): return [] # Win condition safety
		
		if target_area == 2: # AOE
			return living_enemies
		else: # Single Target
			if primary_target.get("current_hp", 0) > 0:
				return [primary_target]
			else:
				return [living_enemies[0]] # Fallback to first alive if target died
				
	# TYPE 2: ALLY
	if target_type in [2, 6]:
		var living_allies = _get_living_units(ally_pool)
		if living_allies.is_empty(): return [] # Game over safety
		
		if target_area == 2: # AOE
			return living_allies
		else: # Single Target
			if primary_target.get("current_hp", 0) > 0:
				return [primary_target]
			else:
				# Fallback to self if the targeted ally somehow died
				return [caster] 
				
	# Fallback catch-all
	return []

func execute_parsed_skill(parsed_skill: Dictionary, caster: Dictionary, primary_target: Dictionary) -> void:
	var effects = parsed_skill.get("effects", [])

	for i in range(effects.size()):
		var effect = effects[i]
		var actual_targets = _resolve_targets(effect.get("target_area", 1), effect.get("target_type", 1), caster, primary_target)
		
		# Delegate to the Action Processor
		var hit_payloads = action_processor.execute_parsed_effect(effect, caster, actual_targets)

		# Process the returned receipts
		for hit in hit_payloads:
			hit["frame_to_execute"] += current_battle_frame
			hit["execute_on_frame"] = hit["frame_to_execute"]
			hit.erase("frame_to_execute")
			pending_hits.append(hit)
