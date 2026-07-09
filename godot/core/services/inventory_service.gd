extends Node
## InventoryService — owns the player's owned items (stackables + equipment
## instances) and the operations that mutate them (load/save, grant, lookup,
## availability filters for equip slots, item-cost lookup).
##
## State previously held by DataManager that now lives here:
##   - owned_items dict, items_updated signal, ITEMS_SNAPSHOT_FILE
##   - snapshot/normalize/load helpers, _grant_instanced_item_local,
##     _equipment_exists, _generate_instance_id, _get_item_cost,
##     get_equipment_template_id, get_available_equipment_for_slot.
##
## Note: `request_buy_item` lives here and uses PlayerProfile for currency
## state plus its own purchase_successful/purchase_failed signals.

signal items_updated(items: Dictionary)
signal purchase_successful()
signal purchase_failed(error_message: String)
signal craft_failed(error_message: String)

const SNAPSHOT_FILE: String = "items.json"

var owned_items: Dictionary = {"stackables": {}, "equipment": []}


# === Snapshot contract ===

func snapshot_payload() -> Dictionary:
	return {
		"owned_items": owned_items.duplicate(true)
	}

func load_from_local() -> void:
	var envelope: Dictionary = Persistence.load_snapshot(SNAPSHOT_FILE)
	if envelope.is_empty():
		owned_items = {"stackables": {}, "equipment": []}
		return

	var data: Variant = envelope.get("data", {})
	owned_items = _normalize_payload(data)

func reset_to_starter() -> void:
	owned_items = {"stackables": {}, "equipment": []}

func emit_updated() -> void:
	items_updated.emit(owned_items)


# === Mutations ===

func generate_instance_id() -> String:
	var parts: Array = []
	var sizes: Array = [4, 2, 2, 2, 6]

	for size in sizes:
		var hex_part: String = ""
		for _i in range(size):
			hex_part += "%02x" % randi_range(0, 255)
		parts.append(hex_part)

	return "%s-%s-%s-%s-%s" % parts

func grant_instanced_items(item_type: String, template_id: String, amount: int) -> Dictionary:
	var grant_count: int = maxi(1, amount)
	var granted_items: Array = []
	if not owned_items.has("equipment") or not (owned_items.get("equipment", []) is Array):
		owned_items["equipment"] = []

	for _i in range(grant_count):
		var item_instance: Dictionary = {
			"instance_id": generate_instance_id(),
			"template_id": str(template_id),
			"item_type": str(item_type),
			"equipped_to": ""
		}
		granted_items.append(item_instance)
		(owned_items["equipment"] as Array).append(item_instance)

	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "grant_instanced_items")

	return {
		"success": true,
		"granted_items": granted_items
	}

func add_stackable(item_id: String, quantity: int) -> void:
	if not owned_items.has("stackables"):
		owned_items["stackables"] = {}
	var current_qty: int = int(owned_items["stackables"].get(item_id, 0))
	owned_items["stackables"][item_id] = current_qty + quantity
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "add_stackable")

func add_equipment_instances(template_id: String, quantity: int) -> Array:
	if not owned_items.has("equipment"):
		owned_items["equipment"] = []
	var added: Array = []
	for _i in range(quantity):
		var new_instance: Dictionary = {
			"instance_id": generate_instance_id(),
			"template_id": template_id
		}
		(owned_items["equipment"] as Array).append(new_instance)
		added.append(new_instance)

	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "add_equipment_instances")
	return added

func consume_stackables_and_save(items: Array) -> void:
	for item in items:
		remove_stackable(item["id"], item["amount"])
	emit_updated()

func remove_stackable(item_id: String, quantity: int) -> void:
	if not owned_items.has("stackables"):
		return
	var current_qty: int = int(owned_items["stackables"].get(item_id, 0))
	if current_qty >= quantity:
		owned_items["stackables"][item_id] = current_qty - quantity
	else:
		owned_items["stackables"][item_id] = 0

	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "remove_stackable")

# === Lookups ===

func get_item_count(item_type: String, item_id: String) -> int:
	if item_type == "20":
		if not owned_items.has("stackables"): return 0
		return int(owned_items["stackables"].get(item_id, 0))
	elif item_type == "21" or item_type == "22":
		if not owned_items.has("equipment"): return 0
		var count: int = 0
		for item in owned_items["equipment"]:
			if item is Dictionary and item.get("template_id", "") == item_id:
				count += 1
		return count
	return 0

func get_item_cost(item_id: String) -> int:
	var item_data: Dictionary = GameDatabase.get_item(int(item_id))
	if item_data.is_empty():
		item_data = GameDatabase.get_equipment(item_id)
	return int(item_data.get("priceBuy", 0))

func has_purchasable_template(item_id: String) -> bool:
	return not GameDatabase.get_item(int(item_id)).is_empty() or not GameDatabase.get_equipment(int(item_id)).is_empty()

func is_equipment_template(item_id: String) -> bool:
	return not GameDatabase.get_equipment(item_id).is_empty()

func equipment_instance_exists(item_id: String) -> bool:
	if not owned_items.has("equipment"):
		return false
	for item in owned_items["equipment"]:
		if item is Dictionary and item.get("instance_id", "") == item_id:
			return true
	return false

func get_equipment_instance(item_id: String) -> Dictionary:
	if not owned_items.has("equipment"):
		return {}
	for item in owned_items["equipment"]:
		if item is Dictionary and item.get("instance_id", "") == item_id:
			return item
	return {}

func get_equipment_template_id(instance_id: String) -> String:
	if not owned_items.has("equipment"): push_error("CRITICAL ERROR: owned_items is missing equipment!")
	var equipment_list = owned_items["equipment"] if owned_items.has("equipment") else []
	for item in equipment_list:
		if not item is Dictionary: continue
		if not item.has("instance_id"): push_error("CRITICAL ERROR: item is missing instance_id!")
		if item["instance_id"] == instance_id:
			if not item.has("template_id"): push_error("CRITICAL ERROR: item is missing template_id!")
			return item["template_id"]
	return ""

func get_available_equipment_for_slot(slot_id: String, allowed_equips: Array) -> Array:
	var available_items: Array = []
	if not owned_items.has("equipment"): push_error("CRITICAL ERROR: owned_items is missing equipment!")
	var equipment_list = owned_items["equipment"] if owned_items.has("equipment") else []
	for item in equipment_list:
		if not item is Dictionary: continue
		if not item.has("instance_id"): push_error("CRITICAL ERROR: item is missing instance_id!")
		var instance_id: String = item["instance_id"]

		if not item.has("template_id"): push_error("CRITICAL ERROR: item is missing template_id!")
		var template_id: String = item["template_id"]

		# Materia instances are stored in the equipment collection; route them separately
		if str(item.get("item_type", "")) == "MATERIA":
			if "ability_" in slot_id:
				var mat_data: Dictionary = GameDatabase.get_materia(int(template_id))
				var combined: Dictionary = mat_data.duplicate()
				combined["instance_id"] = instance_id
				combined["template_id"] = template_id
				combined["item_type"] = "MATERIA"
				combined["equipped_to"] = item.get("equipped_to", null)
				available_items.append(combined)
			continue

		var item_data_dict: Dictionary = GameDatabase.get_equipment(template_id)
		assert(not item_data_dict.is_empty(), "CRITICAL ERROR: equipment template not found: " + template_id)
		if item_data_dict.is_empty():
			push_error("CRITICAL ERROR: equipment template not found: " + template_id)
			continue

		assert(item_data_dict.has("type_id"), "CRITICAL ERROR: item_data_dict is missing type_id!")
		if not item_data_dict.has("type_id"): push_error("CRITICAL ERROR: item_data_dict is missing type_id!")
		var item_type_id: int = item_data_dict["type_id"] # equipCategory

		var is_valid_slot: bool = false

		assert(item_data_dict.has("slot"), "CRITICAL ERROR: item_data_dict is missing slot!")
		if not item_data_dict.has("slot"): push_error("CRITICAL ERROR: item_data_dict is missing slot!")
		var item_slot: String = item_data_dict["slot"]
		if "hand" in slot_id and (item_slot == "Weapon" or item_slot == "Shield"):
			is_valid_slot = true
		elif "head" in slot_id and item_slot == "Headgear":
			is_valid_slot = true
		elif "body" in slot_id and item_slot == "Chest":
			is_valid_slot = true
		elif "acc_" in slot_id and item_slot == "Accessory":
			is_valid_slot = true
		elif "ability_" in slot_id and item_slot == "Materia":
			is_valid_slot = true

		if not is_valid_slot: continue
		if item_type_id not in allowed_equips and item_type_id != -1: continue

		# Combine the instance wrapper data with static stats for the UI
		var combined_item: Dictionary = item_data_dict.duplicate()
		combined_item["instance_id"] = instance_id
		combined_item["template_id"] = template_id
		combined_item["equipped_to"] = item.get("equipped_to", null)

		available_items.append(combined_item)

	return available_items

# === Helpers ===

func _normalize_payload(raw_payload: Variant) -> Dictionary:
	if not (raw_payload is Dictionary):
		return {"stackables": {}, "equipment": []}

	var payload: Dictionary = raw_payload
	var local_stackables: Dictionary = {}
	var local_equipment: Array = []
	if payload.has("owned_items") and payload["owned_items"] is Dictionary:
		var items_dict: Dictionary = payload["owned_items"]
		if items_dict.has("stackables") and items_dict["stackables"] is Dictionary:
			local_stackables = items_dict["stackables"].duplicate(true)
		if items_dict.has("equipment") and items_dict["equipment"] is Array:
			local_equipment = items_dict["equipment"].duplicate(true)

	return {
		"stackables": local_stackables,
		"equipment": local_equipment
	}

# === Shop purchase ===

func request_buy_item(item_id: String, quantity: int) -> void:
	if not has_purchasable_template(item_id):
		purchase_failed.emit("ERR_INSUFFICIENT_RESOURCES")
		return

	var total_cost: int = get_item_cost(item_id) * quantity
	if PlayerProfile.gil < total_cost:
		purchase_failed.emit("ERR_INSUFFICIENT_RESOURCES")
		return

	PlayerProfile.deduct_gil(total_cost)

	if is_equipment_template(item_id):
		add_equipment_instances(item_id, quantity)
	else:
		add_stackable(item_id, quantity)

	emit_updated()
	purchase_successful.emit()

func request_craft_item(recipe_id: String, quantity: int) -> void:
	var recipe_inst = GameDatabase.get_recipe(int(recipe_id))

	var total_cost: int = recipe_inst.get("gil") * quantity
	if PlayerProfile.gil < total_cost:
		craft_failed.emit("ERR_INSUFFICIENT_RESOURCES")
		return
	
	PlayerProfile.deduct_gil(total_cost)

	var material_text = str(recipe_inst.get("material", ""))
	var material_array: Array
	if material_text != null:
		if material_text.contains(','):
			material_array = material_text.split(',')
		else:
			material_array = [material_text]

	for mat in material_array:
		var mat_data = mat.split(':')
		if mat_data[0] == "20": # Item
			var owned_count: int = int(owned_items.get("stackables", {}).get(mat_data[1], 0))
			if owned_count < int(mat_data[2]):
				craft_failed.emit("ERR_INSUFFICIENT_RESOURCES")
				print("Not enough item: " + str(mat_data[1]) + ": " + str(owned_count) + " < " + str(mat_data[2]))
				#return
			#remove_stackable(mat_data[1], int(mat_data[2]))
		if mat_data[0] == "21": # Equipment
			var owned_count: int = int(owned_items.get("equipment", []).filter(func(item): return item.get("template_id") == mat_data[1]).size())
			if owned_count < int(mat_data[2]):
				craft_failed.emit("ERR_INSUFFICIENT_RESOURCES")
				print("Not enough equipment: " + str(mat_data[1]) + ": " + str(owned_count) + " < " + str(mat_data[2]))
				#return
		if mat_data[0] == "22": # Materia
			var owned_count: int = int(owned_items.get("equipment", []).filter(func(item): return item.get("template_id") == mat_data[1]).size())
			if owned_count < int(mat_data[2]):
				craft_failed.emit("ERR_INSUFFICIENT_RESOURCES")
				print("Not enough materia: " + str(mat_data[1]) + ": " + str(owned_count) + " < " + str(mat_data[2]))
				#return
	
	if recipe_inst.get("targetType") == 20:
		print("Add stackable: " + str(recipe_inst.get("targetId")))
		add_stackable(str(recipe_inst.get("targetId")), quantity)
	if recipe_inst.get("targetType") == 21:
		print("Add equipment: " + str(recipe_inst.get("targetId")))
		add_equipment_instances(str(recipe_inst.get("targetId")), quantity)
	if recipe_inst.get("targetType") == 22:
		print("Add equipment: " + str(recipe_inst.get("targetId")))
		grant_instanced_items("MATERIA", str(recipe_inst.get("targetId")), quantity)
