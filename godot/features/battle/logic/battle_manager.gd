extends Node

signal battle_state_ready
signal enemy_hp_changed(new_hp: int, max_hp: int, hp_percent: int)
signal turn_changed(new_turn: int)
signal unit_stats_updated(index: int, unit_name: String, cur_hp: int, max_hp: int, cur_mp: int, max_mp: int, cur_limit: int, max_limit: int)
signal attack_landed(attacker_index: int, target_index: int, damage: int)

enum BattleState { INIT, PLAYER_TURN, RESOLVING_TURN, ENEMY_TURN, BATTLE_OVER }

const ENEMY_ATTACK_DELAY_FRAMES: int = 60

var current_state: BattleState = BattleState.INIT
var player_units_acted_this_turn: Array = []
var current_battle_frame: int = 0
var pending_hits: Array[Dictionary] = []

var enemy_data: Dictionary = {}
var enemy_current_hp: int = 0
var enemy_max_hp: int = 0

var party_data: Array = []
var turn_count: int = 1

func _ready() -> void:
	pass

func _physics_process(_delta: float) -> void:
	if current_state != BattleState.PLAYER_TURN and current_state != BattleState.ENEMY_TURN:
		return

	current_battle_frame += 1

	for i in range(pending_hits.size() - 1, -1, -1):
		var hit: Dictionary = pending_hits[i]
		if hit.get("execute_on_frame", 0) <= current_battle_frame:
			var target_index: int = hit.get("target_index", -1)
			var damage: int = hit.get("damage", 0)
			var attacker_index: int = hit.get("attacker_index", -1)

			if target_index == -1:
				enemy_current_hp = maxi(0, enemy_current_hp - damage)
				set_enemy_hp(enemy_current_hp)
			else:
				var target_unit: Dictionary = party_data[target_index]
				target_unit["current_hp"] = maxi(0, target_unit["current_hp"] - damage)
				request_unit_stats(target_index)

			attack_landed.emit(attacker_index, target_index, damage)
			pending_hits.remove_at(i)

	_check_turn_progression()


func initialize_battle(dungeon_id: String) -> void:
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
				var template_id = str(battle_unit.get("unit_id", ""))
				var template = DataManager.game_data_units.get(template_id, {})

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

				party_data.append(battle_unit)
			else:
				party_data.append({})

	# Load enemy data
	var dungeon_data = DataManager.game_data_dungeons.get(dungeon_id, {})
	var monsters_in_dungeon = dungeon_data.get("monsters", [])

	if monsters_in_dungeon.size() > 0:
		enemy_data = monsters_in_dungeon[0] # Take first monster for now
		enemy_max_hp = int(enemy_data.get("hp", 1000))
		enemy_current_hp = enemy_max_hp

	current_state = BattleState.PLAYER_TURN
	player_units_acted_this_turn.clear()
	current_battle_frame = 0
	pending_hits.clear()

	turn_count = 1
	battle_state_ready.emit()

func set_enemy_hp(new_hp: int) -> void:
	enemy_current_hp = new_hp
	var pct: int = 0
	if enemy_max_hp > 0:
		pct = int((float(enemy_current_hp) / float(enemy_max_hp)) * 100.0)
	enemy_hp_changed.emit(enemy_current_hp, enemy_max_hp, pct)

func request_basic_attack(attacker_index: int) -> void:
	if current_state != BattleState.PLAYER_TURN:
		return
	if attacker_index in player_units_acted_this_turn:
		return

	player_units_acted_this_turn.append(attacker_index)

	# Keep accepting inputs for other units by not changing state here

	var attacker_data: Dictionary = party_data[attacker_index]

	# Fetch unit's frame data
	var template_id: String = str(attacker_data.get("unit_id", ""))
	var template: Dictionary = DataManager.game_data_units.get(template_id, {})

	var current_rarity: int = int(attacker_data.get("current_rarity", 1))
	var entries: Dictionary = template.get("entries", {})
	var target_entry: Dictionary = {}

	for entry_key in entries.keys():
		var entry: Dictionary = entries[entry_key]
		if int(entry.get("rarity", 0)) == current_rarity:
			target_entry = entry
			break

	var attack_frames: Array = target_entry.get("attack_frames", [30])
	var attack_damage: Array = target_entry.get("attack_damage", [[100]])
	var damage_percentages: Array = attack_damage[0] if attack_damage.size() > 0 else [100]

	# Attacker ATK (must exist)
	var attacker_stats: Dictionary = attacker_data.get("final_stats", {})
	assert(attacker_stats.has("ATK"), "Player must have ATK")
	var attacker_atk: int = attacker_stats.get("ATK")

	# Enemy DEF (fallback to 5 since enemy stats are missing)
	var enemy_def: int = enemy_data.get("DEF", 5)

	# Calculate total base damage (minimum 1)
	var total_damage: int = maxi(1, attacker_atk - enemy_def)

	# Queue hits
	for i in range(attack_frames.size()):
		var hit_frame: int = attack_frames[i]
		var pct: int = damage_percentages[i] if i < damage_percentages.size() else 100
		var hit_damage: int = maxi(1, int(total_damage * (float(pct) / 100.0)))

		pending_hits.append({
			"execute_on_frame": current_battle_frame + hit_frame,
			"damage": hit_damage,
			"attacker_index": attacker_index,
			"target_index": -1
		})

func _check_turn_progression() -> void:
	if not pending_hits.is_empty():
		return

	if current_state == BattleState.PLAYER_TURN:
		var all_acted: bool = true

		for i in range(party_data.size()):
			var unit: Dictionary = party_data[i]
			# A living unit is not empty, has current_hp, and current_hp > 0
			if not unit.is_empty() and unit.has("current_hp") and unit.get("current_hp") > 0:
				if i not in player_units_acted_this_turn:
					all_acted = false
					break

		if all_acted:
			current_state = BattleState.ENEMY_TURN
			_execute_enemy_turn()
	elif current_state == BattleState.ENEMY_TURN:
		# Transition back to PLAYER_TURN
		player_units_acted_this_turn.clear()
		turn_count += 1
		turn_changed.emit(turn_count)
		current_state = BattleState.PLAYER_TURN

func _execute_enemy_turn() -> void:
	var living_player_indices: Array[int] = []
	for i in range(party_data.size()):
		var unit: Dictionary = party_data[i]
		if not unit.is_empty() and unit.has("current_hp") and unit.get("current_hp") > 0:
			living_player_indices.append(i)

	if living_player_indices.size() > 0:
		var random_idx: int = randi() % living_player_indices.size()
		var target_index: int = living_player_indices[random_idx]
		var target_unit: Dictionary = party_data[target_index]

		# Enemy ATK (fallback to 10)
		var enemy_atk: int = enemy_data.get("ATK", 10)

		# Player DEF (must exist)
		var target_stats: Dictionary = target_unit.get("final_stats", {})
		assert(target_stats.has("DEF"), "Player must have DEF")
		var target_def: int = target_stats.get("DEF")

		# Calculate damage (minimum 1)
		var damage: int = maxi(1, enemy_atk - target_def)

		# Push a single hit to pending_hits
		pending_hits.append({
			"execute_on_frame": current_battle_frame + ENEMY_ATTACK_DELAY_FRAMES,
			"damage": damage,
			"attacker_index": -1,
			"target_index": target_index
		})

func request_unit_stats(index: int) -> void:
	if index < 0 or index >= party_data.size():
		return

	var unit_data: Dictionary = party_data[index]
	if unit_data.is_empty():
		return

	var template_id: String = str(unit_data.get("unit_id", ""))
	var template: Dictionary = DataManager.game_data_units.get(template_id, {})

	var unit_name: String = template.get("name", "Unknown")
	var cur_hp: int = unit_data.get("current_hp", 0)
	var max_hp: int = unit_data.get("max_hp", 1)
	var cur_mp: int = unit_data.get("current_mp", 0)
	var max_mp: int = unit_data.get("max_mp", 1)
	var cur_limit: int = unit_data.get("limit_gauge", 0)
	var max_limit: int = unit_data.get("max_limit", 100)

	unit_stats_updated.emit(index, unit_name, cur_hp, max_hp, cur_mp, max_mp, cur_limit, max_limit)
