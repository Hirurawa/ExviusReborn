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
signal wave_changed(current_wave: int, total_waves: int)

enum BattleState { INIT, PLAYER_TURN, RESOLVING_TURN, ENEMY_TURN, BATTLE_OVER }
enum CombatAction { ATTACK, DEFEND, SKILL, ITEM }

const ENEMY_ATTACK_DELAY_FRAMES: int = 60

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

func _ready() -> void:
	pass

func _physics_process(_delta: float) -> void:
	if current_state != BattleState.PLAYER_TURN and current_state != BattleState.ENEMY_TURN:
		return

	current_battle_frame += 1

	for i in range(pending_hits.size() - 1, -1, -1):
		var hit: Dictionary = pending_hits[i]
		if hit.get("execute_on_frame", 0) <= current_battle_frame:
			var target_team: String = hit.get("target_team", "enemy")
			var target_index: int = hit.get("target_index", 0)
			var damage: int = hit.get("damage", 0)
			var attacker_team: String = hit.get("attacker_team", "player")
			var attacker_index: int = hit.get("attacker_index", 0)

			var target_array = enemy_units if target_team == "enemy" else player_units
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

					target["last_hit_frame"] = current_battle_frame
					target["last_attacker_index"] = current_attacker
					chain_count_emitted = target["chain_count"]

					target["current_hp"] = maxi(0, target.get("current_hp", 0) - final_damage)
					if target_team == "enemy":
						set_enemy_hp(target_index, target["current_hp"])
					else:
						# For UI stats, we still need the original party_data index
						# For now, search it by instance_id or let request_unit_stats find it
						var p_idx = party_data.find(target)
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
				if final_stats.is_empty():
					final_stats = StatCalculator.calculate_final_stats(battle_unit)

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

			var parsed_data: Dictionary = OpcodeParser.parse_skill(target_skill_data)
			print("Parsed Skill: ", parsed_data)

			# Attempt to get targeting data from the queue, fallback to enemy 0 for now
			var target_team: String = attacker_data.get("queued_target_team", "enemy")
			var target_idx: int = attacker_data.get("queued_target_index", 0)

			# Route the skill to the execution pipeline
			# Note: We hardcode "player" here assuming only players use the UI queue right now
			execute_parsed_skill(parsed_data, "player", attacker_index, target_team, target_idx)

		_check_turn_progression()
		return
	elif action == CombatAction.ATTACK:
		# Keep accepting inputs for other units by not changing state here
		unit_action_started.emit(attacker_index, CombatAction.ATTACK)
		
		# Build a dummy effect so it goes through our standard pipeline
		var dummy_effect = {
			"type": "BASIC_ATTACK",
			"modifier": 1.0,
			"target_area": 1,
			"target_type": 1
		}
		
		# Retrieve the actual queued target index
		var target_index = attacker_data.get("queued_target_index", 0)
		
		var attack_frames = attacker_data.get("attack_frames", [30])
		var attack_damage = attacker_data.get("attack_damage", [[100]])
		
		# Find internal index if needed
		var p_idx = player_units.find(attacker_data)
		var internal_attacker_index = p_idx if p_idx != -1 else attacker_index

		_route_effect(dummy_effect, attack_damage, attack_frames, "player", internal_attacker_index, [target_index], "enemy")

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
				var p_idx = party_data.find(unit)
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
		var target_unit: Dictionary = player_units[target_index]

		# Let's assume enemy index 0 for now
		var attacker_index: int = 0
		
		# Emit signal so the UI can play the attack animation
		enemy_action_started.emit(attacker_index, CombatAction.ATTACK)

		var dummy_effect = {
			"type": "BASIC_ATTACK",
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
		
		_route_effect(dummy_effect, attack_damage, attack_frames, "enemy", attacker_index, [target_index], "player")

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
	# TODO: Stop turn queue, show Game Over UI

func _trigger_wave_clear() -> void:
	print("BattleManager: Wave %d cleared!" % current_wave)

	if current_wave >= total_waves:
		_trigger_mission_complete()
	else:
		_spawn_next_wave()

func _trigger_mission_complete() -> void:
	print("BattleManager: Final wave cleared. Initiating mission rewards...")
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

func _spawn_enemies_for_wave(dungeon_data: Dictionary) -> void:
	enemy_units.clear()
	var monsters_in_dungeon = dungeon_data.get("monsters", [])

	if monsters_in_dungeon.size() > 0:
		var spawn_count = randi() % 3 + 1 # Random number between 1 and 3

		for i in range(spawn_count):
			var random_monster_idx = randi() % monsters_in_dungeon.size()
			var selected_monster_data = monsters_in_dungeon[random_monster_idx]

			var fully_hydrated_enemy = _generate_enemy_data(selected_monster_data)
			enemy_units.append(fully_hydrated_enemy)


func _resolve_targets(target_area: int, target_type: int, caster_team: String, caster_index: int, primary_team: String, primary_index: int) -> Array:
	var targets = []
	var enemy_pool = enemy_units
	var ally_pool = player_units if caster_team == "player" else enemy_units # Adjust if enemies cast buffs on themselves

	match target_area:
		1: # Single Target
			var pool = ally_pool if target_type in [2, 3, 4, 6] else enemy_units
			if primary_index < pool.size():
				targets.append(primary_index)
		2: # AOE
			var pool = ally_pool if target_type in [2, 6] else enemy_units
			for i in range(pool.size()):
				targets.append(i)
		3: # Self
			targets.append(caster_index)

	return targets

func execute_parsed_skill(parsed_skill: Dictionary, caster_team: String, caster_idx: int, primary_target_team: String, primary_target_idx: int) -> void:
	var effects = parsed_skill.get("effects", [])

	for i in range(effects.size()):
		var effect = effects[i]
		var all_attack_damage = effect.get("attack_damage", [])
		var all_attack_frames = effect.get("attack_frames", [])

		var actual_targets = _resolve_targets(effect.get("target_area", 1), effect.get("target_type", 1), caster_team, caster_idx, primary_target_team, primary_target_idx)

		_route_effect(effect, all_attack_damage, all_attack_frames, caster_team, caster_idx, actual_targets, primary_target_team)

func _route_effect(effect: Dictionary, attack_damage: Array, attack_frames: Array, caster_team: String, caster_idx: int, targets: Array, target_team: String) -> void:
	match effect.get("type"):
		"MAGIC_DAMAGE", "PHYSICAL_DAMAGE", "BASIC_ATTACK":
			var modifier = effect.get("modifier", 1.0)
			
			var active_roster = player_units if caster_team == "player" else enemy_units
			var caster_data = active_roster[caster_idx]
			var caster_stats = caster_data.get("final_stats", caster_data) # Fallback to base dict if final_stats missing

			for target_idx in targets:
				var target_roster = enemy_units if target_team == "enemy" else player_units
				var target_data = target_roster[target_idx]
				var target_stats = target_data.get("final_stats", target_data)

				var raw_damage = EffectProcessor.calculate_raw_damage(effect.get("type"), modifier, caster_stats, target_stats)
				var hit_payloads = EffectProcessor.generate_hit_payloads(raw_damage, attack_damage, attack_frames, caster_team, caster_idx, target_team, target_idx)

				# Add our current frame offset and push to the engine's hit queue
				for hit in hit_payloads:
					hit["frame_to_execute"] += current_battle_frame
					# Note: changed current_frame to current_battle_frame to match the file's variable name.
					# pending_hits items need execute_on_frame as expected by _physics_process
					hit["execute_on_frame"] = hit["frame_to_execute"]
					hit.erase("frame_to_execute") # Just to clean it up so it matches what we check
					pending_hits.append(hit)

		_:
			print("BattleManager: No routing logic yet for effect type: ", effect.get("type"))
