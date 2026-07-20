extends Node
## PartyService — owns the parties array, selected party index, save/load,
## normalization, and assignment helpers.
##
## Signals:
##   parties_updated()               — emitted whenever the parties list changes
##   active_party_changed(party_idx) — emitted when the selected slot moves
##   party_save_requested(parties)   — convenience signal so UI panels can ask
##                                     for a deferred save without calling
##                                     `save_parties` directly. Connected to
##                                     `save_parties` inside `_ready`.

signal parties_updated()
signal party_save_requested(new_parties: Array)
signal active_party_changed(party_index: int)

const SNAPSHOT_FILE: String = "parties.json"
const SLOT_COUNT: int = 5

var parties: Array = []
var selected_party_index: int = 0

func _ready() -> void:
	party_save_requested.connect(save_parties)

# === State management ===

func reset_to_starter(starter_parties: Array) -> void:
	parties = starter_parties
	selected_party_index = 0

func emit_all() -> void:
	parties_updated.emit()
	active_party_changed.emit(selected_party_index)

func snapshot_payload() -> Dictionary:
	var normalized_parties: Array = _normalize_parties_array(parties)
	var normalized_selected: int = 0
	if not normalized_parties.is_empty():
		normalized_selected = clampi(selected_party_index, 0, normalized_parties.size() - 1)
	return {
		"parties": normalized_parties,
		"selected_party_index": normalized_selected
	}

func load_from_local() -> void:
	var payload: Dictionary = _load_from_local()
	parties = payload.get("parties", [])
	selected_party_index = clamp_selected_party_index(int(payload.get("selected_party_index", 0)))

func build_default_parties(rain_instance_id: String, lasswell_instance_id: String) -> Array:
	var generated_parties: Array = []
	for i in range(SLOT_COUNT):
		generated_parties.append({
			"name": "Party %d" % (i + 1),
			"units": ["", "", "", "", ""],
			"espers": ["", "", "", "", ""]
		})

	if not generated_parties.is_empty():
		generated_parties[0]["units"][0] = rain_instance_id
		generated_parties[0]["units"][1] = lasswell_instance_id

	return generated_parties


# === Public API ===

func clamp_selected_party_index(candidate_index: int) -> int:
	if parties.is_empty():
		return 0
	return clampi(candidate_index, 0, parties.size() - 1)


func get_selected_party_index() -> int:
	return clamp_selected_party_index(selected_party_index)

func set_selected_party_index(new_index: int) -> bool:
	var next_index: int = clamp_selected_party_index(new_index)
	if selected_party_index == next_index:
		return false

	selected_party_index = next_index
	active_party_changed.emit(selected_party_index)
	return true

func get_active_party() -> Dictionary:
	if parties.is_empty():
		return {}

	var index: int = clamp_selected_party_index(selected_party_index)
	if index < 0 or index >= parties.size():
		return {}

	var party_entry: Variant = parties[index]
	if party_entry is Dictionary:
		return party_entry
	return {}

func save_parties(new_parties: Array) -> Dictionary:
	var normalized_parties: Array = _normalize_parties_array(new_parties)
	var selected_for_save: int = 0
	if not normalized_parties.is_empty():
		selected_for_save = clampi(selected_party_index, 0, normalized_parties.size() - 1)

	var previous_selected_local: int = selected_party_index
	parties = normalized_parties
	selected_party_index = clamp_selected_party_index(selected_for_save)
	parties_updated.emit()
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "parties_saved")
	if selected_party_index != previous_selected_local:
		active_party_changed.emit(selected_party_index)
	return {
		"success": true,
		"parties": parties,
		"selected_party_index": selected_party_index
	}


func assign_unit_to_party(party_index: int, slot_index: int, instance_id: String) -> void:
	if party_index < 0 or party_index >= parties.size():
		return
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return

	var new_parties: Array = _normalize_parties_array(parties)
	new_parties[party_index]["units"][slot_index] = instance_id
	party_save_requested.emit(new_parties)


func assign_esper_to_party(party_index: int, slot_index: int, summon_id: String) -> void:
	if party_index < 0 or party_index >= parties.size():
		return
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return

	var normalized_summon_id: String = summon_id.strip_edges()
	if normalized_summon_id != "" and not EsperService.is_esper_unlocked(normalized_summon_id):
		return

	var new_parties: Array = _normalize_parties_array(parties)
	var target_espers: Array = new_parties[party_index].get("espers", [])

	# Keep espers unique inside the same party by removing any existing assignment first.
	if normalized_summon_id != "":
		for i in range(target_espers.size()):
			if str(target_espers[i]) == normalized_summon_id:
				target_espers[i] = ""

	target_espers[slot_index] = normalized_summon_id
	new_parties[party_index]["espers"] = target_espers
	party_save_requested.emit(new_parties)


func is_unit_assigned_to_any_party(unit_instance_id: String) -> bool:
	for party_entry in parties:
		if not (party_entry is Dictionary):
			continue
		var units_value: Variant = party_entry.get("units", [])
		if units_value is Array:
			for assigned_instance_id in units_value:
				if str(assigned_instance_id) == unit_instance_id:
					return true
	return false


func get_units_in_party(party_index: int) -> Array:
	"""Returns array of unit instance IDs assigned to a specific party."""
	if party_index < 0 or party_index >= parties.size():
		return []

	var party_entry: Variant = parties[party_index]
	if not (party_entry is Dictionary):
		return []

	var units_value: Variant = party_entry.get("units", [])
	if not (units_value is Array):
		return []

	var assigned_units: Array = []
	for unit_id in units_value:
		var normalized_id: String = str(unit_id).strip_edges()
		if normalized_id != "":
			assigned_units.append(normalized_id)

	return assigned_units


func get_units_in_party_excluding_slot(party_index: int, slot_index: int) -> Array:
	"""Returns array of unit instance IDs in a party, excluding a specific slot.
	Useful for preventing duplicates when replacing/editing a unit in a slot."""
	if party_index < 0 or party_index >= parties.size():
		return []
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return []

	var party_entry: Variant = parties[party_index]
	if not (party_entry is Dictionary):
		return []

	var units_value: Variant = party_entry.get("units", [])
	if not (units_value is Array):
		return []

	var assigned_units: Array = []
	for i in range(units_value.size()):
		if i == slot_index:
			continue
		var unit_id: String = str(units_value[i]).strip_edges()
		if unit_id != "":
			assigned_units.append(unit_id)

	return assigned_units


# === Normalization helpers ===

func normalize_parties_array(raw_parties: Variant) -> Array:
	return _normalize_parties_array(raw_parties)


func _normalize_parties_payload(raw_payload: Variant) -> Dictionary:
	if not (raw_payload is Dictionary):
		return {"parties": [], "selected_party_index": 0}

	var payload: Dictionary = raw_payload
	var local_parties: Array = _normalize_parties_array(payload.get("parties", []))

	var local_selected: int = int(payload.get("selected_party_index", 0))
	if local_parties.is_empty():
		local_selected = 0
	else:
		local_selected = clampi(local_selected, 0, local_parties.size() - 1)

	return {
		"parties": local_parties,
		"selected_party_index": local_selected
	}


func _normalize_party_slots(raw_slots: Variant, slot_count: int) -> Array:
	var normalized: Array = []
	for _i in range(slot_count):
		normalized.append("")

	if not (raw_slots is Array):
		return normalized

	var source_slots: Array = raw_slots
	for i in range(min(slot_count, source_slots.size())):
		normalized[i] = str(source_slots[i])

	return normalized


func _normalize_party_entry(raw_party: Variant, fallback_index: int) -> Dictionary:
	var party_dict: Dictionary = {}
	if raw_party is Dictionary:
		party_dict = (raw_party as Dictionary).duplicate(true)

	var fallback_name: String = "Party %d" % (fallback_index + 1)
	return {
		"name": str(party_dict.get("name", fallback_name)),
		"units": _normalize_party_slots(party_dict.get("units", []), SLOT_COUNT),
		"espers": _normalize_party_slots(party_dict.get("espers", []), SLOT_COUNT)
	}


func _normalize_parties_array(raw_parties: Variant) -> Array:
	if not (raw_parties is Array):
		return []

	var source_parties: Array = raw_parties
	var normalized: Array = []
	for i in range(source_parties.size()):
		normalized.append(_normalize_party_entry(source_parties[i], i))

	return normalized


func _load_from_local() -> Dictionary:
	var envelope: Dictionary = Persistence.load_snapshot(SNAPSHOT_FILE)
	if envelope.is_empty():
		return {"parties": [], "selected_party_index": 0}

	var data: Variant = envelope.get("data", {})
	return _normalize_parties_payload(data)
