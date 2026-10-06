extends Control

const ItemScene = preload("res://features/shared/Item.tscn")

@onready var equip_selection_list: GridContainer = $VBoxContainer/ScrollContainer/EquipListContainer
@onready var close_btn: Button = $VBoxContainer/CloseButton

var current_unit_inst: Dictionary = {}
var current_slot_id: String = ""
var allowed_types: Array = []
var _pending_item_id: String = ""
## The unit's gear, resolved once for the hand checks of every candidate.
var _equipped_items: Array = []

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

	_equipped_items = StatCalculator.resolve_equipped_items(current_unit_inst)

	_populate_list()

func _populate_list() -> void:
	for child in equip_selection_list.get_children():
		child.queue_free()
	
	var remove_button: TextureButton = TextureButton.new()
	remove_button.texture_normal = ResourceLoader.load("res://assets/ui/common/remove_long.tres")
	remove_button.texture_pressed = ResourceLoader.load("res://assets/ui/common/remove_long2.tres")
	equip_selection_list.add_child(remove_button)
	remove_button.pressed.connect(_on_equip_item_selected.bind("")) 
	
	#var remove_cell: Control = ItemScene.instantiate()
	#remove_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	#equip_selection_list.add_child(remove_cell)
	#remove_cell.setup_placeholder("Remove", "")
	#remove_cell.set_clickable(true)
	#remove_cell.pressed.connect(_on_equip_item_selected.bind(""))

	var allowed_equips = Array(current_unit_inst.get("equipCategories").split(',')).map(func(x): return int(x))

	var available_items: Array = InventoryService.get_available_equipment_for_slot(current_slot_id, allowed_equips)

	for item_dict in available_items:
		if not _passes_hand_rules(item_dict):
			continue

		var item_instance_id: String = str(item_dict.get("instance_id", ""))
		var item_cell: Control = ItemScene.instantiate()
		item_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		equip_selection_list.add_child(item_cell)
		if str(item_dict.get("item_type", "")) == "MATERIA":
			var icon_name: String = str(item_dict.get("iconFile", ""))
			var icon_path: String = "res://assets/abilities/" + icon_name if icon_name != "" else ""
			var detail_text: String = item_dict.get("explainShort", "No description")
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

## Hand slots list only what the unit can hold with its other hand: no second weapon it
## cannot dual wield, no second shield. Items locked out by a two-handed weapon stay
## listed; equipping one explains why it failed.
func _passes_hand_rules(item_dict: Dictionary) -> bool:
	if not (current_slot_id in EquipmentValidator.HAND_SLOTS):
		return true
	var reason: String = EquipmentValidator.hand_problem(current_unit_inst, _equipped_items, current_slot_id, str(item_dict.get("template_id", "")))
	return reason != EquipmentValidator.ERR_DUAL_WIELD_REQUIRED and reason != EquipmentValidator.ERR_TWO_SHIELDS

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
		"ERR_TWO_SHIELDS":
			return "A unit can't hold two shields."
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
		var name_value: String = str(unit.get("unitName", ""))
		if name_value != "":
			return name_value
		return str(unit.get("unitName", "another unit"))
	return "another unit"
