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
	# Load party data
	# Note: DataManager.parties could be structured as an array of Party Dictionaries
	# If DataManager.parties[0] is a Dictionary (like { "units": [...] }), extract the array.
	if DataManager.parties.size() > 0:
		var first_party = DataManager.parties[0]
		if typeof(first_party) == TYPE_DICTIONARY:
			party_data = first_party.get("units", []).duplicate()
		elif typeof(first_party) == TYPE_ARRAY:
			party_data = first_party.duplicate()
		else:
			party_data = []
	else:
		party_data = []

	# Enhance party data with stats
	for unit in party_data:
		var template_id = str(unit.get("unit_id", ""))
		var template = DataManager.game_data_units.get(template_id, {})

		# Set placeholder max HP/MP logic since actual calculation is complex
		var entries = template.get("entries", {})
		var max_rarity = 1
		for k in entries.keys():
			max_rarity = max(max_rarity, int(k))

		var stats = entries.get(str(unit.get("current_rarity", max_rarity)), {}).get("stats", {})
		var base_hp = stats.get("HP", [100])[0] if typeof(stats.get("HP")) == TYPE_ARRAY else 100
		var base_mp = stats.get("MP", [10])[0] if typeof(stats.get("MP")) == TYPE_ARRAY else 10

		unit["max_hp"] = base_hp
		unit["current_hp"] = base_hp
		unit["max_mp"] = base_mp
		unit["current_mp"] = base_mp
		unit["limit_gauge"] = 0
		unit["max_limit"] = 100 # arbitrary placeholder

	# Load enemy data
	var dungeon_data = DataManager.game_data_dungeons.get(dungeon_id, {})
	var monsters_in_dungeon = dungeon_data.get("monsters", [])

	if monsters_in_dungeon.size() > 0:
		enemy_data = monsters_in_dungeon[0] # Take first monster for now
		enemy_max_hp = int(enemy_data.get("hp", 1000))
		enemy_current_hp = enemy_max_hp

	turn_count = 1
	battle_state_ready.emit()
