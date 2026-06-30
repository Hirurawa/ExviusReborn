extends Control

const ItemScene = preload("res://features/shared/Item.tscn")

@onready var equip_selection_list: GridContainer = $VBoxContainer/ScrollContainer/EquipListContainer
@onready var close_btn: Button = $VBoxContainer/CloseButton

var current_unit_inst: Dictionary = {}
var current_slot_id: String = ""
var allowed_types: Array = []
var _pending_item_id: String = ""
var _dual_wield_cache: Dictionary = {}

var _conflict_dialog: ConfirmationDialog
var _error_dialog: AcceptDialog

func _ready() -> void:
	close_btn.pressed.connect(func(): UIManager.pop())

	_conflict_dialog = ConfirmationDialog.new()
	_conflict_dialog.title = "Already Equipped"
	_conflict_dialog.confirmed.connect(_on_conflict_confirmed)
	add_child(_conflict_dialog)

	_error_dialog = AcceptDialog.new()
	_error_dialog.title = "Cannot Equip"
	add_child(_error_dialog)

	UnitService.equip_successful.connect(_on_equip_successful)
	UnitService.equip_failed.connect(_on_equip_failed)
	UnitService.equip_conflict.connect(_on_equip_conflict)

func _exit_tree() -> void:
	if UnitService.equip_successful.is_connected(_on_equip_successful):
		UnitService.equip_successful.disconnect(_on_equip_successful)
	if UnitService.equip_failed.is_connected(_on_equip_failed):
		UnitService.equip_failed.disconnect(_on_equip_failed)
	if UnitService.equip_conflict.is_connected(_on_equip_conflict):
		UnitService.equip_conflict.disconnect(_on_equip_conflict)

func init_scene(params: Dictionary) -> void:
	current_unit_inst = params.get("unit_inst", {})
	current_slot_id = params.get("slot_id", "")
	allowed_types = params.get("allowed_types", [])

	_dual_wield_cache = EquipmentValidator.get_dual_wield_allowed_type_ids(current_unit_inst)

	_populate_list()

func _populate_list() -> void:
	for child in equip_selection_list.get_children():
		child.queue_free()

	var remove_cell: Control = ItemScene.instantiate()
	remove_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_selection_list.add_child(remove_cell)
	remove_cell.setup_placeholder("Remove", "")
	remove_cell.set_clickable(true)
	remove_cell.pressed.connect(_on_equip_item_selected.bind(""))

	var unit_data: Dictionary = StaticData.game_data_units.get(current_unit_inst.get("unit_id", ""), {})
	var allowed_equips: Array = unit_data.get("equip", [])

	var available_items: Array = InventoryService.get_available_equipment_for_slot(current_slot_id, allowed_equips)

	for item_dict in available_items:
		if not _passes_dual_wield_filter(item_dict):
			continue

		var item_instance_id: String = str(item_dict.get("instance_id", ""))
		var item_cell: Control = ItemScene.instantiate()
		item_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		equip_selection_list.add_child(item_cell)
		if str(item_dict.get("item_type", "")) == "MATERIA":
			var icon_name: String = str(item_dict.get("icon", ""))
			var icon_path: String = "res://assets/abilities/" + icon_name if icon_name != "" else ""
			var effects: Array = item_dict.get("effects", [])
			var detail_text: String = str(effects[0]) if not effects.is_empty() else ""
			item_cell.setup_placeholder(str(item_dict.get("name", "Unknown Materia")), detail_text, {
				"icon_path": icon_path,
				"equipped_to_unit_id": str(item_dict.get("equipped_to", ""))
			})
		else:
			var display_options: Dictionary = {
				"show_slot_badge": false,
				"equipped_to_unit_id": str(item_dict.get("equipped_to", ""))
			}
			item_cell.setup_from_item_data(item_dict, display_options)
		item_cell.set_clickable(true)
		item_cell.pressed.connect(_on_equip_item_selected.bind(item_instance_id))

func _passes_dual_wield_filter(item_dict: Dictionary) -> bool:
	# Only constrain weapon candidates for hand slots.
	if not (current_slot_id in ["r_hand", "l_hand"]):
		return true
	if str(item_dict.get("slot", "")) != "Weapon":
		return true
	if bool(item_dict.get("is_twohanded", false)):
		return true
	# One-handed weapon: ok if the *other* hand isn't already holding a one-handed
	# weapon, OR the unit can dual-wield both types.
	var equipment: Dictionary = current_unit_inst.get("equipment", {})
	var other_hand: String = "l_hand" if current_slot_id == "r_hand" else "r_hand"
	var other_item_id: String = str(equipment.get(other_hand, ""))
	if other_item_id == "":
		return true
	var other_template_id: String = InventoryService.get_equipment_template_id(other_item_id)
	var other_template: Dictionary = StaticData.game_data_equipment.get(other_template_id, {})
	if other_template.is_empty():
		return true
	if str(other_template.get("slot", "")) != "Weapon" or bool(other_template.get("is_twohanded", false)):
		return true
	var incoming_type: int = int(item_dict.get("type_id", -1))
	var other_type: int = int(other_template.get("type_id", -1))
	return _dual_wield_permits(incoming_type) and _dual_wield_permits(other_type)

func _dual_wield_permits(weapon_type_id: int) -> bool:
	if not bool(_dual_wield_cache.get("has", false)):
		return false
	if bool(_dual_wield_cache.get("allows_any", false)):
		return true
	return weapon_type_id in (_dual_wield_cache.get("type_ids", []) as Array)

func _on_equip_item_selected(item_id: String) -> void:
	_pending_item_id = item_id
	var instance_id: String = current_unit_inst.get("instance_id", "")
	UnitService.request_equip_item(instance_id, current_slot_id, item_id)

func _on_equip_successful() -> void:
	UIManager.pop()

func _on_equip_failed(error_message: String) -> void:
	_error_dialog.dialog_text = _error_message_for_code(error_message)
	_error_dialog.popup_centered()

func _on_equip_conflict(_target_unit_id: String, _slot_id: String, item_id: String, conflicting_unit_id: String) -> void:
	_pending_item_id = item_id
	var other_name: String = _unit_display_name(conflicting_unit_id)
	_conflict_dialog.dialog_text = "This equipment is currently equipped to %s.\nUnequip it and move it to this unit?" % other_name
	_conflict_dialog.popup_centered()

func _on_conflict_confirmed() -> void:
	var instance_id: String = current_unit_inst.get("instance_id", "")
	UnitService.request_equip_item(instance_id, current_slot_id, _pending_item_id, true)

func _error_message_for_code(code: String) -> String:
	match code:
		"ERR_DUAL_WIELD_REQUIRED":
			return "This unit can't dual-wield this weapon."
		"ERR_TWO_HANDED_LOCKED":
			return "This slot is occupied by a two-handed weapon."
		"ERR_EQUIPMENT_ALREADY_IN_USE":
			return "That item is already equipped in another slot on this unit."
		"ERR_EQUIPMENT_NOT_FOUND":
			return "That item is no longer available."
		"ERR_UNIT_NOT_FOUND":
			return "Unit not found."
		_:
			return "Equip failed: %s" % code

func _unit_display_name(unit_instance_id: String) -> String:
	for unit in UnitService.owned_units_ids:
		if not (unit is Dictionary):
			continue
		if str(unit.get("instance_id", "")) != unit_instance_id:
			continue
		var name_value: String = str(unit.get("name", ""))
		if name_value != "":
			return name_value
		var unit_data: Dictionary = StaticData.game_data_units.get(str(unit.get("unit_id", "")), {})
		return str(unit_data.get("name", "another unit"))
	return "another unit"
