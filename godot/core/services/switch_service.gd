extends Node

const SNAPSHOT_FILE: String = "switches.json"

var opened_switches: Array = []

func snapshot_payload() -> Dictionary:
	return {
		"opened_switches": opened_switches.duplicate(true)
	}

func load_progress() -> void:
	var envelope: Dictionary = Persistence.load_snapshot(SNAPSHOT_FILE)
	if envelope.is_empty():
		opened_switches = []
		return

	var data: Variant = envelope.get("data", {})
	if not (data is Dictionary):
		opened_switches = []
		return

	var payload: Dictionary = data
	var loaded_switches: Variant = payload.get("opened_switches", [])
	if loaded_switches is Array:
		opened_switches = loaded_switches.duplicate(true)
	else:
		opened_switches = []

func unlock_switches(switches_str: String) -> bool:
	if switches_str == "":
		return false

	var any_unlocked: bool = false
	var switch_parts: PackedStringArray = switches_str.split(",")

	for part in switch_parts:
		var switch_id: String = part.strip_edges()
		if switch_id != "" and not opened_switches.has(switch_id):
			opened_switches.append(switch_id)
			any_unlocked = true

	return any_unlocked
