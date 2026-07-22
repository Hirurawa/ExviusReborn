extends Node

@warning_ignore("unused_signal")
signal enemy_damaged(monster_id, hit)
@warning_ignore("unused_signal")
signal enemy_defeated(monster_id, hit)
@warning_ignore("unused_signal")
signal ally_defeated()
@warning_ignore("unused_signal")
signal magic_used(spell_data)
@warning_ignore("unused_signal")
signal ability_used(spell_data)
@warning_ignore("unused_signal")
signal item_used(item_id)
@warning_ignore("unused_signal")
signal limitburst_used(lb_id)
@warning_ignore("unused_signal")
signal esper_evoked(esper_id)
@warning_ignore("unused_signal")
signal mission_completed(party_data, turn_count)

var _repeat_record: Dictionary = {}


## Saved after a complete manual submission, including the user's initial Auto
## batch. It lives here so Reload/Repeat survive battle scenes, but not app restarts.
func save_repeat_record(save_scope: String, party_signature: Array, commands_by_unit_id: Dictionary) -> void:
	_repeat_record = {
		"save_scope": save_scope,
		"party_signature": party_signature.duplicate(true),
		"commands_by_unit_id": commands_by_unit_id.duplicate(true),
	}


## Returns the whole command set only for the exact account + ordered party.
## A mismatch invalidates everything so unchanged slots can never partially reload.
func get_repeat_commands(save_scope: String, party_signature: Array) -> Dictionary:
	if _repeat_record.is_empty():
		return {}
	if str(_repeat_record.get("save_scope", "")) != save_scope \
	or _repeat_record.get("party_signature", []) != party_signature:
		clear_repeat_record()
		return {}
	var commands: Variant = _repeat_record.get("commands_by_unit_id", {})
	return (commands as Dictionary).duplicate(true) if commands is Dictionary else {}


func clear_repeat_record() -> void:
	_repeat_record.clear()
