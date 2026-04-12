extends Node

signal battle_state_ready
signal enemy_hp_changed(new_hp: int, max_hp: int, hp_percent: int)
signal turn_changed(new_turn: int)
signal unit_stats_updated(index: int, unit_name: String, cur_hp: int, max_hp: int, cur_mp: int, max_mp: int, cur_limit: int, max_limit: int)

var enemy_data: Dictionary = {}
var enemy_current_hp: int = 0
var enemy_max_hp: int = 0

var party_data: Array = []
var turn_count: int = 1

func _ready() -> void:
	pass

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

	turn_count = 1
	battle_state_ready.emit()

func set_enemy_hp(new_hp: int) -> void:
	enemy_current_hp = new_hp
	var pct: int = 0
	if enemy_max_hp > 0:
		pct = int((float(enemy_current_hp) / float(enemy_max_hp)) * 100.0)
	enemy_hp_changed.emit(enemy_current_hp, enemy_max_hp, pct)

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
