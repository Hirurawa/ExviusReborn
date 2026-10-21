extends Node

signal switches_unlocked

const SNAPSHOT_FILE: String = "switches.json"

var opened_switches: Array = []

func snapshot_payload() -> Dictionary:
	return {
		"opened_switches": opened_switches.duplicate(true)
	}

## A new game starts with no switches (a save loaded earlier this run must not leak
## its story into the new one).
func reset() -> void:
	opened_switches = []


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

func is_unlocked(switch_info: Variant) -> bool:
	if switch_info == null:
		return false

	var switch_str: String = str(switch_info).strip_edges()
	if switch_str == "" or switch_str == "null":
		return false

	if switch_str == "0":
		return true

	var switch_parts: PackedStringArray = switch_str.split(",")
	for part in switch_parts:
		var switch_id: String = part.strip_edges()
		if switch_id != "" and not opened_switches.has(switch_id):
			return false

	return true

func unlock_switches(switches_str: String, source_event: String = "unlock_switches") -> bool:
	if switches_str == "":
		return false

	var any_unlocked: bool = false
	var switch_parts: PackedStringArray = switches_str.split(",")

	for part in switch_parts:
		var switch_id: String = part.strip_edges()
		if switch_id != "" and not opened_switches.has(switch_id):
			opened_switches.append(switch_id)
			any_unlocked = true

	if any_unlocked:
		switches_unlocked.emit()
		Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), source_event)

	return any_unlocked


## Turns switches off again (a cutscene can set a story switch to 0).
func lock_switches(switches_str: String, source_event: String = "lock_switches") -> bool:
	var any_locked: bool = false
	for part in switches_str.split(","):
		var switch_id: String = part.strip_edges()
		if switch_id != "" and opened_switches.has(switch_id):
			opened_switches.erase(switch_id)
			any_locked = true
	if any_locked:
		switches_unlocked.emit()
		Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), source_event)
	return any_locked


## The switches that are on, the way event pages read them: { switch id (int): 1 }.
func as_event_switches() -> Dictionary:
	var out: Dictionary = {}
	for switch_id in opened_switches:
		var text: String = str(switch_id)
		if text.is_valid_int():
			out[int(text)] = 1
	return out
