extends Node

signal battle_state_ready
signal enemy_hp_changed(enemy_index: int, new_hp: int, max_hp: int, hp_percent: int)
signal turn_changed(new_turn: int)
signal unit_stats_updated(index: int, unit_name: String, cur_hp: int, max_hp: int, cur_mp: int, max_mp: int, cur_limit: int, max_limit: int)
signal attack_landed(attacker_team: String, attacker_index: int, target_team: String, target_index: int, damage: int)
signal unit_acted(index: int)
signal unit_action_started(unit_index: int, action: CombatAction)
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
			if target_index >= 0 and target_index < target_array.size():
				var target = target_array[target_index]
				if not target.is_empty():
					target["current_hp"] = maxi(0, target.get("current_hp", 0) - damage)
					if target_team == "enemy":
						set_enemy_hp(target_index, target["current_hp"])
					else:
						# For UI stats, we still need the original party_data index
						# For now, search it by instance_id or let request_unit_stats find it
						var p_idx = party_data.find(target)
						if p_idx != -1:
							request_unit_stats(p_idx)

			attack_landed.emit(attacker_team, attacker_index, target_team, target_index, damage)
			pending_hits.remove_at(i)

	_check_turn_progression()


func initialize_battle(mission_id: String) -> void:
	
	current_mission_id = mission_id
	var mission_data = DataManager.game_data_missions.get(str(mission_id), {})

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

				party_data.append(battle_unit)
			else:
				party_data.append({})

	player_units.clear()
	for unit in party_data:
		if not unit.is_empty():
			player_units.append(unit)

	# Load enemy data
	enemy_units.clear()
	var dungeon_id = str(mission_data.get("dungeon_id", ""))
	var dungeon_data = DataManager.game_data_dungeons.get(str(dungeon_id), {})
	var monsters_in_dungeon = dungeon_data.get("monsters", [])

	if monsters_in_dungeon.size() > 0:
		var dungeon_monster_data = monsters_in_dungeon[0] # Take first monster for now

		var global_monster_data = {}
		var monster_name = dungeon_monster_data.get("name", "")
		if monster_name != "":
			for monster in DataManager.game_data_monsters:
				if typeof(monster) == TYPE_DICTIONARY and str(monster.get("name", "")) == str(monster_name):
					global_monster_data = monster.duplicate(true)
					break

		# Merge dungeon specific data into global monster data
		var enemy_data = global_monster_data.duplicate(true)
		for key in dungeon_monster_data:
			enemy_data[key] = dungeon_monster_data[key]

		var enemy_max_hp = int(enemy_data.get("hp", 1000))
		enemy_data["max_hp"] = enemy_max_hp
		enemy_data["current_hp"] = enemy_max_hp

		enemy_units.append(enemy_data)

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

		_check_turn_progression()
		return
	elif action == CombatAction.ATTACK:
		# Keep accepting inputs for other units by not changing state here
		
		# Fetch unit's frame data directly from the hydrated instance
		var attack_frames: Array = attacker_data.get("attack_frames", [30])
		var attack_damage: Array = attacker_data.get("attack_damage", [[100]])
		var damage_percentages: Array = attack_damage[0] if attack_damage.size() > 0 else [100]

		# Attacker ATK (must exist)
		var attacker_stats: Dictionary = attacker_data.get("final_stats", {})
		assert(attacker_stats.has("ATK"), "Player must have ATK")
		var attacker_atk: int = attacker_stats.get("ATK")

		# Target Enemy (default to index 0 for now)
		var target_index: int = 0
		var enemy_def: int = 5
		if enemy_units.size() > 0:
			enemy_def = enemy_units[target_index].get("DEF", 5)

		# Calculate total base damage (minimum 1)
		var total_damage: int = maxi(1, attacker_atk - enemy_def)

		unit_action_started.emit(attacker_index, CombatAction.ATTACK)

		# Find internal index if needed, but hit queue expects the attacker index logic correctly mapped below.
		# The engine loop uses player_units while UI uses party_data indices. We use party_data index for emit and the hit payload.
		var p_idx = player_units.find(attacker_data)
		var internal_attacker_index = p_idx if p_idx != -1 else attacker_index

		# Queue hits
		for i in range(attack_frames.size()):
			var hit_frame: int = attack_frames[i]
			var pct: int = damage_percentages[i] if i < damage_percentages.size() else 100
			var hit_damage: int = maxi(1, int(total_damage * (float(pct) / 100.0)))

			pending_hits.append({
				"execute_on_frame": current_battle_frame + hit_frame,
				"damage": hit_damage,
				"attacker_team": "player",
				"attacker_index": internal_attacker_index,
				"target_team": "enemy",
				"target_index": target_index
			})

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
		var enemy_atk: int = 10
		if enemy_units.size() > 0:
			enemy_atk = enemy_units[attacker_index].get("ATK", 10)

		# Player DEF (must exist)
		var target_stats: Dictionary = target_unit.get("final_stats", {})
		assert(target_stats.has("DEF"), "Player must have DEF")
		var target_def: int = target_stats.get("DEF")

		# Calculate damage (minimum 1)
		var damage: int = maxi(1, enemy_atk - target_def)
		
		if target_unit.get("is_defending", false):
			damage = int(damage * 0.5)

		# Push a single hit to pending_hits
		pending_hits.append({
			"execute_on_frame": current_battle_frame + ENEMY_ATTACK_DELAY_FRAMES,
			"damage": damage,
			"attacker_team": "enemy",
			"attacker_index": attacker_index,
			"target_team": "player",
			"target_index": target_index
		})

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

	enemy_units.clear()

	var mission_data = DataManager.game_data_missions.get(str(current_mission_id), {})
	var dungeon_id = str(mission_data.get("dungeon_id", ""))
	var dungeon_data = DataManager.game_data_dungeons.get(str(dungeon_id), {})
	var monsters_in_dungeon = dungeon_data.get("monsters", [])

	if monsters_in_dungeon.size() > 0:
		var dungeon_monster_data = monsters_in_dungeon[0]

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

		enemy_units.append(enemy_data)

	wave_changed.emit(current_wave, total_waves)

	current_state = BattleState.PLAYER_TURN
	player_units_acted_this_turn.clear()
	current_battle_frame = 0
	pending_hits.clear()

	battle_state_ready.emit()

	# Only unlock after everything is fully set up
	is_transitioning = false
