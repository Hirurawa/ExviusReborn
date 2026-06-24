extends RefCounted
class_name CombatInventory

## In-battle consumable inventory: a snapshot of stackable item quantities the
## party brought into combat. Owned by BattleUI; lives only for the duration of
## a single battle and isn't persisted (consumption is reconciled with
## InventoryService at battle end).

var _quantities: Dictionary = {}


## Builds the inventory from the player's selected combat-item slot loadout,
## filtered to items that are actually usable in combat and currently owned.
func reload_from_services() -> void:
	_quantities.clear()
	var stackables: Dictionary = InventoryService.owned_items.get("stackables", {})
	var selected_slots: Array = CombatItemsService.combat_items

	for slot_value in selected_slots:
		var item_id: String = str(slot_value)
		if item_id == "":
			continue

		var quantity: int = int(stackables.get(item_id, 0))
		if quantity <= 0:
			continue
		var item_data: Dictionary = GameDatabase.get_item(item_id)
		if item_data.is_empty():
			continue
		if item_data.get("usable_in_combat", false) == true and item_data.has("effects_raw"):
			_quantities[item_id] = quantity


func quantity(item_id: String) -> int:
	return int(_quantities.get(item_id, 0))


func has_any(item_id: String) -> bool:
	return _quantities.has(item_id) and int(_quantities[item_id]) > 0


## Returns true if the item was available and was decremented.
func consume(item_id: String) -> bool:
	if not has_any(item_id):
		return false
	_quantities[item_id] = int(_quantities[item_id]) - 1
	return true


## Restores a previously consumed item (e.g. when a queued action is cancelled).
func refund(item_id: String) -> void:
	if _quantities.has(item_id):
		_quantities[item_id] = int(_quantities[item_id]) + 1
	else:
		_quantities[item_id] = 1


## Exposes the underlying dict for read-only iteration by UI populators.
func entries() -> Dictionary:
	return _quantities
