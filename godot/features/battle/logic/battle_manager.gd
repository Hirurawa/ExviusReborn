extends Node

signal battle_state_ready
signal enemy_hp_changed(new_hp: int, max_hp: int)
signal turn_changed(new_turn: int)

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

				# Set placeholder max HP/MP logic since actual calculation is complex
				var entries = template.get("entries", {})
				var max_rarity = 1
				for k in entries.keys():
					max_rarity = max(max_rarity, int(k))

				var stats = entries.get(str(battle_unit.get("current_rarity", max_rarity)), {}).get("stats", {})
				var base_hp = stats.get("HP", [100])[0] if typeof(stats.get("HP")) == TYPE_ARRAY else 100
				var base_mp = stats.get("MP", [10])[0] if typeof(stats.get("MP")) == TYPE_ARRAY else 10

				battle_unit["max_hp"] = base_hp
				battle_unit["current_hp"] = base_hp
				battle_unit["max_mp"] = base_mp
				battle_unit["current_mp"] = base_mp
				battle_unit["limit_gauge"] = 0
				battle_unit["max_limit"] = 100 # arbitrary placeholder

				party_data.append(battle_unit)

	# Load enemy data
	var dungeon_data = DataManager.game_data_dungeons.get(dungeon_id, {})
	var monsters_in_dungeon = dungeon_data.get("monsters", [])

	if monsters_in_dungeon.size() > 0:
		enemy_data = monsters_in_dungeon[0] # Take first monster for now
		enemy_max_hp = int(enemy_data.get("hp", 1000))
		enemy_current_hp = enemy_max_hp

	turn_count = 1
	battle_state_ready.emit()
