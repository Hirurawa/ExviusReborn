extends Node
## CombatItemsService — owns the 10-slot combat item bar (selection,
## persistence, validation against owned stackables).
##
## State previously held by DataManager that now lives here:
##   - SLOT_COUNT, SNAPSHOT_FILE, combat_items array
##   - combat_items_updated / combat_items_loaded / combat_items_saved signals
##
## Validates picks against StaticData.game_data_items and InventoryService.owned_items
## (inventory still owned by DataManager until InventoryService lands).

signal combat_items_updated(slots: Array)
signal combat_items_loaded(slots: Array)
signal combat_items_saved(slots: Array)

const SLOT_COUNT: int = 10
const SNAPSHOT_FILE: String = "combat_items.json"

var combat_items: Array = ["", "", "", "", "", "", "", "", "", ""]


# === Public API ===

func set_combat_item(slot_index: int, item_id: String) -> void:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return

	var normalized_item_id: String = item_id.strip_edges()
	if normalized_item_id != "":
		if not StaticData.game_data_items.has(normalized_item_id):
			normalized_item_id = ""
		else:
			var stackables: Dictionary = InventoryService.owned_items.get("stackables", {})
			if int(stackables.get(normalized_item_id, 0)) <= 0:
				normalized_item_id = ""

	if str(combat_items[slot_index]) == normalized_item_id:
		return

	combat_items[slot_index] = normalized_item_id
	combat_items_updated.emit(combat_items.duplicate())
	_save_to_local()


func clear_all() -> void:
	for i in range(SLOT_COUNT):
		combat_items[i] = ""
	combat_items_updated.emit(combat_items.duplicate())
	_save_to_local()


func reset_to_empty() -> void:
	combat_items = ["", "", "", "", "", "", "", "", "", ""]


# === Snapshot contract (called by DataManager during init / save_all) ===

func snapshot_payload() -> Dictionary:
	return {
		"slots": combat_items.duplicate()
	}


func load_from_local() -> Array:
	var envelope: Dictionary = Persistence.load_snapshot(SNAPSHOT_FILE)
	if envelope.is_empty():
		return _empty_slots()

	var data: Variant = envelope.get("data", {})
	if not (data is Dictionary):
		return _empty_slots()

	var slots: Variant = data.get("slots", [])
	combat_items = _normalize_slots(slots)
	return combat_items


func emit_loaded() -> void:
	combat_items_loaded.emit(combat_items.duplicate())


# === Helpers ===

func _save_to_local() -> void:
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "combat_items_saved")
	combat_items_saved.emit(combat_items.duplicate())


func _normalize_slots(raw_slots: Variant) -> Array:
	var normalized: Array = _empty_slots()
	if not (raw_slots is Array):
		return normalized

	var source_slots: Array = raw_slots
	for i in range(min(SLOT_COUNT, source_slots.size())):
		normalized[i] = str(source_slots[i])

	return normalized


func _empty_slots() -> Array:
	return ["", "", "", "", "", "", "", "", "", ""]
