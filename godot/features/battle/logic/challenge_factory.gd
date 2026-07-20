class_name ChallengeFactory

static func create(parameter: String) -> ChallengeTracker:
	# Handle default "Complete the quest"
	if parameter == "68":
		return ChallengeTracker.new(true) # Defaults to completed
		
	var tracker = ChallengeTracker.new()
	var parts = parameter.split(":")
	var type = parts[0]

	match type:
		"0": # Use an item
			tracker.bind_signal(BattleEvents.item_used, func(_item_id):
				tracker.is_completed = true
			)
		"1": # No items
			tracker.is_completed = true # Assume success until failed
			tracker.bind_signal(BattleEvents.item_used, func(_item_id):
				tracker.is_failed = true
			)
		"2": # Use a potion
			var req_item = int(parts[1])
			tracker.bind_signal(BattleEvents.item_used, func(item_id):
				if req_item == item_id:
					tracker.is_completed = true
			)
		"5": # Use magic
			tracker.bind_signal(BattleEvents.magic_used, func(_spell_data):
				tracker.is_completed = true
			)
		"6": # No magic
			tracker.is_completed = true
			tracker.bind_signal(BattleEvents.magic_used, func(_spell_data):
				tracker.is_failed = true
			)
		"7": # Use <magicName>
			var req_magic = int(parts[1])
			tracker.bind_signal(BattleEvents.magic_used, func(spell_data):
				if req_magic == int(spell_data.get("resolved_action_id")):
					tracker.is_completed = true
			)
		"8": # No dispelga
			var req_magic = int(parts[1])
			tracker.bind_signal(BattleEvents.magic_used, func(spell_data):
				if req_magic == int(spell_data.get("resolved_acion_id")):
					tracker.is_failed = true
			)
		"12": # No recovery magic
			var req_magic = int(parts[1])
			tracker.bind_signal(BattleEvents.magic_used, func(spell_data):
				if req_magic == spell_data.get("yjY4GK3X"):
					tracker.is_failed = true
			)
		"13": # Use <magicType(s)>
			var req_magic = int(parts[1])
			tracker.bind_signal(BattleEvents.magic_used, func(spell_data):
				if req_magic == spell_data.get("magicType"):
					tracker.is_completed = true
			)
		"14": # No <magicType(s)> magic
			var req_magic = int(parts[1])
			tracker.bind_signal(BattleEvents.magic_used, func(spell_data):
				if req_magic == spell_data.get("magicType"):
					tracker.is_failed = true
			)
		"15": # Defeat <monsterName> with magic
			pass
		"16": # Use a limit burst
			tracker.bind_signal(BattleEvents.limitburst_used, func(_lb_id):
				tracker.is_completed = true
			)
		"17": # No limit bursts
			tracker.bind_signal(BattleEvents.limitburst_used, func(_lb_id):
				tracker.is_failed = true
			)
		"18": # Defeat <monsterName> with a limit burst
			pass
		"21": # Use <abilityName>
			var req_ability = int(parts[1])
			tracker.bind_signal(BattleEvents.ability_used, func(spell_data):
				if req_ability == int(spell_data.get("resolved_acion_id")):
					tracker.is_completed = true
			)
		"26": # Deal <elementName(s)> damage to an enemy
			var req_elem = int(parts[1])
			tracker.bind_signal(BattleEvents.enemy_damaged, func(_target, hit):
				if req_elem in hit.get("element"):
					tracker.is_completed = true
			)
		"28": # Evoke an esper
			tracker.bind_signal(BattleEvents.esper_evoked, func(_esper_id):
				tracker.is_completed = true
			)
		"29": # No espers
			tracker.bind_signal(BattleEvents.esper_evoked, func(_esper_id):
				tracker.is_failed = true
			)
		"30": # Evoke <esperName(s)>
			var req_elem = int(parts[1])
			tracker.bind_signal(BattleEvents.esper_evoked, func(esper_id):
				if req_elem == esper_id:
					tracker.is_completed = true
			)
		"32": # Defeat <monsterName> with an esper
			pass
		"33": # Clear without an ally being KO'd
			tracker.is_completed = true
			tracker.bind_signal(BattleEvents.ally_defeated, func():
				tracker.is_failed = true
			)
		"34": # Party of <num> or more
			var req_elem = int(parts[1])
			tracker.bind_signal(BattleEvents.mission_completed, func(party_data, _turn_count):
				if req_elem < party_data.filter(func(d): return not d.is_empty()).size():
					tracker.is_completed = true
			)
		"35": # Party of <num> or less
			var req_elem = int(parts[1])
			tracker.bind_signal(BattleEvents.mission_completed, func(party_data, _turn_count):
				if req_elem > party_data.filter(func(d): return not d.is_empty()).size():
					tracker.is_completed = true
			)
		"36": # <unitName> in party
			var req_elem = int(parts[1])
			tracker.bind_signal(BattleEvents.mission_completed, func(party_data, _turn_count):
				if party_data.filter(func(d): return d.get("unitSeries") == req_elem):
					tracker.is_completed = true
			)
		"38": # No continues
			tracker.bind_signal(BattleEvents.mission_completed, func(_party_data, _turn_count):
				tracker.is_completed = true
			)
		"40": # Use no more than <num> items
			var req_count = int(parts[1])
			tracker.bind_signal(BattleEvents.item_used, func(_item_id):
				tracker.counter += 1
				if tracker.counter > req_count:
					tracker.is_failed = true
			)
		"41": # Use magic <num> or more times
			var req_count = int(parts[1])
			tracker.bind_signal(BattleEvents.magic_used, func(_spell_data):
				tracker.counter += 1
				if tracker.counter > req_count:
					tracker.is_completed = true
			)
		"45": # Evoke an esper <num> times or more
			var req_count = int(parts[1])
			tracker.bind_signal(BattleEvents.esper_evoked, func(_esper_id):
				tracker.counter += 1
				if tracker.counter >= req_count:
					tracker.is_completed = true
			)
		"49": # Use <num> or more limit bursts
			var req_count = int(parts[1])
			tracker.bind_signal(BattleEvents.limitburst_used, func(_lb_id):
				tracker.counter += 1
				if tracker.counter > req_count:
					tracker.is_completed = true
			)
		"59": # Deal <elementName(s)> damage <num> times or more each to an enemy
			pass
		"65":
			pass
		"69":
			pass
		"71":
			pass
		"75": # Clear within <num> turns
			var req_elem = int(parts[1])
			tracker.bind_signal(BattleEvents.mission_completed, func(_party_data, turn_count):
				if req_elem < turn_count:
					tracker.is_completed = true
			)
		"76": # Defeat a <monsterName>
			var req_count = int(parts[1])
			tracker.bind_signal(BattleEvents.enemy_defeated, func(monster_id, _hit):
				if req_count == monster_id:
					tracker.is_completed = true
			)
		"77": # Defeat <monsterName>'s party within <num> turns
			pass
		"122": # Get a chain of <num> or more in 1 turn
			pass
		"132": # Activate an element chain <num> times or more in 1 turn
			pass
		_:
			push_warning("Unimplemented challenge type: ", type)
	
	return tracker
