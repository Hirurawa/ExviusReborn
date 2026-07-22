extends Node

const BATTLE_UI_SCENE := preload("res://features/battle/ui/BattleUI.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	BattleEvents.clear_repeat_record()
	Persistence.active_local_save_id = "repeat_test"
	SkillResolver.load_schemas()
	var ui: Control = BATTLE_UI_SCENE.instantiate()
	add_child(ui)
	await get_tree().process_frame
	var manager: Node = ui.battle_manager
	var unit_a: Dictionary = _unit("A", manager.CombatAction.ATTACK)
	var unit_b: Dictionary = _unit("B", manager.CombatAction.ATTACK)
	_set_party(manager, [unit_a, unit_b, {}])

	var signature: Array = ["A", "B", ""]

	# A user-triggered Auto batch is a completed manual selection and is saved.
	unit_a["queued_action"] = manager.CombatAction.DEFEND
	unit_b["queued_action"] = manager.CombatAction.DEFEND
	ui.auto_button.set_pressed_no_signal(true)
	manager.pending_hits.append({"execute_on_frame": 999999})
	ui._execute_auto_turn(true)
	assert(BattleEvents.get_repeat_commands("repeat_test", signature).size() == 2)
	manager.pending_hits.clear()

	# Auto continues after a wave reset, but turning it off leaves the next turn idle.
	manager.enemy_units = [_enemy()]
	manager.current_state = manager.BattleState.ENEMY_TURN
	manager.player_units_acted_this_turn.clear()
	manager._reset_unit_queued_action(unit_a)
	manager._reset_unit_queued_action(unit_b)
	manager.pending_hits.append({"execute_on_frame": 999999})
	ui._on_wave_changed()
	manager.current_state = manager.BattleState.PLAYER_TURN
	await get_tree().process_frame
	assert(manager.player_units_acted_this_turn == [0, 1])
	assert(BattleEvents.get_repeat_commands("repeat_test", signature)["A"]["action"] == manager.CombatAction.DEFEND)
	manager.pending_hits.clear()
	ui.auto_button.set_pressed_no_signal(false)
	manager.current_state = manager.BattleState.PLAYER_TURN
	manager.player_units_acted_this_turn.clear()
	ui._on_turn_changed(2)
	await get_tree().process_frame
	assert(manager.player_units_acted_this_turn.is_empty())
	manager._reset_unit_queued_action(unit_a)
	manager._reset_unit_queued_action(unit_b)

	var commands: Dictionary = {
		"A": _command(manager.CombatAction.DEFEND),
		"B": _command(manager.CombatAction.DEFEND),
	}
	BattleEvents.save_repeat_record("repeat_test", signature, commands)

	# Reload and Repeat share restoration; only Repeat adds execution.
	ui._on_reload_pressed()
	assert(unit_a["queued_action"] == manager.CombatAction.DEFEND)
	assert(unit_b["queued_action"] == manager.CombatAction.DEFEND)
	assert(manager.player_units_acted_this_turn.is_empty())
	manager._reset_unit_queued_action(unit_a)
	manager._reset_unit_queued_action(unit_b)
	manager.pending_hits.append({"execute_on_frame": 999999})
	ui._on_repeat_pressed()
	assert(manager.player_units_acted_this_turn == [0, 1])
	manager.pending_hits.clear()

	# The record survives a battle-scene boundary for the same ordered party.
	assert(BattleEvents.get_repeat_commands("repeat_test", signature).size() == 2)

	# A valid saved spell is restored by Reload and executed only by Repeat.
	var magic_unit: Dictionary = _unit("A", manager.CombatAction.ATTACK)
	magic_unit["final_stats"]["skills"]["magic"] = [{"id": 10170}]
	_set_party(manager, [magic_unit, unit_b, {}])
	manager.enemy_units = [_enemy()]
	var banishga_command: Dictionary = _skill_command(manager, "magic", "10170")
	banishga_command["action_name"] = "Banishga"
	BattleEvents.save_repeat_record("repeat_test", signature, {"A": banishga_command})
	ui._on_reload_pressed()
	assert(magic_unit["queued_action"] == manager.CombatAction.SKILL)
	assert(manager.player_units_acted_this_turn.is_empty())
	manager._reset_unit_queued_action(magic_unit)
	ui._on_repeat_pressed()
	assert(manager.player_units_acted_this_turn == [0])
	assert(magic_unit["current_mp"] == 70)
	manager.pending_hits.clear()

	# Replacing or reordering invalidates the entire record and executes no defaults.
	var replacement: Dictionary = _unit("D", manager.CombatAction.ATTACK)
	_set_party(manager, [magic_unit, replacement, {}])
	assert(ui._restore_saved_commands().is_empty())
	assert(replacement["queued_action"] == manager.CombatAction.ATTACK)
	assert(manager.player_units_acted_this_turn.is_empty())

	manager.current_state = manager.BattleState.PLAYER_TURN
	manager.player_units_acted_this_turn.clear()
	manager._reset_unit_queued_action(unit_a)
	manager._reset_unit_queued_action(unit_b)
	_set_party(manager, [unit_a, unit_b, {}])
	BattleEvents.save_repeat_record("repeat_test", signature, commands)
	_set_party(manager, [unit_b, unit_a, {}])
	assert(ui._restore_saved_commands().is_empty())
	assert(BattleEvents.get_repeat_commands("repeat_test", ["B", "A", ""]).is_empty())
	assert(manager.player_units_acted_this_turn.is_empty())
	assert(unit_a["queued_action"] == manager.CombatAction.ATTACK)
	assert(unit_b["queued_action"] == manager.CombatAction.ATTACK)
	assert(ui._restore_saved_commands().is_empty()) # no saved record

	# Invalid resources are rejected through the real restoration path.
	var low_mp_battle_unit: Dictionary = _unit("A", manager.CombatAction.ATTACK)
	low_mp_battle_unit["current_mp"] = 20
	low_mp_battle_unit["final_stats"]["skills"]["magic"] = [{"id": 10170}]
	_set_party(manager, [low_mp_battle_unit, unit_b, {}])
	manager.enemy_units = [_enemy()]
	BattleEvents.save_repeat_record("repeat_test", signature, {"A": _skill_command(manager, "magic", "10170")})
	assert(ui._restore_saved_commands().is_empty())
	assert(manager.player_units_acted_this_turn.is_empty())
	assert(low_mp_battle_unit["queued_action"] == manager.CombatAction.ATTACK)

	var lb_unit: Dictionary = _unit("A", manager.CombatAction.ATTACK)
	lb_unit["limitBurstId"] = "100000102"
	lb_unit["limit_gauge"] = 0
	lb_unit["max_limit"] = 10
	_set_party(manager, [lb_unit, unit_b, {}])
	BattleEvents.save_repeat_record("repeat_test", signature, {"A": _skill_command(manager, "limitburst", "100000102")})
	assert(ui._restore_saved_commands().is_empty())
	assert(lb_unit["queued_action"] == manager.CombatAction.ATTACK)

	# Reload reserves an item once; Repeat reuses that queued reservation and acts.
	var item_unit: Dictionary = _unit("A", manager.CombatAction.ATTACK)
	_set_party(manager, [item_unit, unit_b, {}])
	var item_command: Dictionary = _skill_command(manager, "item", "300210", "player", 0)
	item_command["action"] = manager.CombatAction.ITEM
	item_command["action_name"] = "Potion"
	item_command["payload"]["original_item_id"] = "101000100"
	BattleEvents.save_repeat_record("repeat_test", signature, {"A": item_command})
	ui.combat_inventory._quantities.clear()
	assert(ui._restore_saved_commands().is_empty())
	ui.combat_inventory._quantities["101000100"] = 1
	item_command["target_index"] = 2
	BattleEvents.save_repeat_record("repeat_test", signature, {"A": item_command})
	assert(ui._restore_saved_commands().is_empty())
	assert(ui.combat_inventory.quantity("101000100") == 1)
	item_command["target_index"] = 0
	BattleEvents.save_repeat_record("repeat_test", signature, {"A": item_command})
	ui._on_reload_pressed()
	assert(item_unit["queued_action"] == manager.CombatAction.ITEM)
	assert(ui.combat_inventory.quantity("101000100") == 0)
	manager.pending_hits.append({"execute_on_frame": 999999})
	ui._on_repeat_pressed()
	assert(manager.player_units_acted_this_turn == [0])
	assert(ui.combat_inventory.quantity("101000100") == 0)
	manager.pending_hits.clear()

	item_unit["current_hp"] = 0
	manager.current_state = manager.BattleState.PLAYER_TURN
	manager.player_units_acted_this_turn.clear()
	assert(ui._restore_saved_commands().is_empty())
	assert(manager.player_units_acted_this_turn.is_empty())

	# Partial manual turns cannot replace the record; complete ones can.
	_set_party(manager, [unit_a, unit_b, {}])
	manager.current_state = manager.BattleState.PLAYER_TURN
	manager.player_units_acted_this_turn = [0]
	_set_last_action(unit_a, manager.CombatAction.DEFEND)
	_set_last_action(unit_b, manager.CombatAction.DEFEND)
	BattleEvents.clear_repeat_record()
	ui._save_repeat_record_if_turn_complete()
	assert(BattleEvents.get_repeat_commands("repeat_test", signature).is_empty())
	manager.player_units_acted_this_turn = [0, 1]
	ui._save_repeat_record_if_turn_complete()
	assert(BattleEvents.get_repeat_commands("repeat_test", signature).size() == 2)

	print("repeat_commands_test: PASS")
	ui.free()
	get_tree().quit()


func _unit(instance_id: String, action: int) -> Dictionary:
	return {
		"instance_id": instance_id,
		"current_hp": 100,
		"current_mp": 100,
		"queued_action": action,
		"queued_action_name": "",
		"queued_action_id": "",
		"queued_target_team": "enemy",
		"queued_target_index": 0,
		"attackFrames": "999999:100",
		"final_stats": {
			"stats": {"ATK": 100, "DEF": 100, "MAG": 100, "SPR": 100},
			"skills": {"magic": [], "ability": []},
		},
	}


func _enemy() -> Dictionary:
	return {
		"id": "test_enemy",
		"index": 0,
		"team": "enemy",
		"current_hp": 1000,
		"max_hp": 1000,
		"chain_count": 0,
		"last_hit_frame": -100,
		"last_attacker_index": -1,
		"final_stats": {"stats": {"ATK": 10, "DEF": 10, "MAG": 10, "SPR": 10}},
	}


func _command(action: int) -> Dictionary:
	return {
		"action": action,
		"action_name": "",
		"action_id": "",
		"payload": {},
		"target_team": "enemy",
		"target_index": 0,
	}


func _skill_command(manager: Node, source_type: String, action_id: String, target_team: String = "enemy", target_index: int = 0) -> Dictionary:
	return {
		"action": manager.CombatAction.SKILL,
		"action_name": "",
		"action_id": action_id,
		"payload": {"source_type": source_type},
		"target_team": target_team,
		"target_index": target_index,
	}


func _set_party(manager: Node, party: Array) -> void:
	manager.party_data = party
	manager.player_units = []
	for unit_index in range(party.size()):
		var unit: Dictionary = party[unit_index]
		if not unit.is_empty():
			unit["index"] = unit_index
			manager.player_units.append(unit)
	manager.current_state = manager.BattleState.PLAYER_TURN
	manager.player_units_acted_this_turn.clear()


func _set_last_action(unit: Dictionary, action: int) -> void:
	unit["last_action"] = action
	unit["last_action_name"] = ""
	unit["last_action_id"] = ""
	unit["last_payload"] = {}
	unit["last_target_team"] = "enemy"
	unit["last_target_index"] = 0
