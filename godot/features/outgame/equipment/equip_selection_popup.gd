extends Control

const ItemScene = preload("res://features/shared/Item.tscn")

@onready var equip_selection_list: GridContainer = $VBoxContainer/ScrollContainer/EquipListContainer
@onready var close_btn: Button = $VBoxContainer/CloseButton

var current_unit_inst: Dictionary = {}
var current_slot_id: String = ""
var allowed_types: Array = []

func _ready() -> void:
	close_btn.pressed.connect(func(): UIManager.pop())

func init_scene(params: Dictionary) -> void:
	current_unit_inst = params.get("unit_inst", {})
	current_slot_id = params.get("slot_id", "")
	allowed_types = params.get("allowed_types", [])

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
		var item_instance_id: String = str(item_dict.get("instance_id", ""))
		var item_cell: Control = ItemScene.instantiate()
		item_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		equip_selection_list.add_child(item_cell)
		if str(item_dict.get("item_type", "")) == "MATERIA":
			var icon_name: String = str(item_dict.get("icon", ""))
			var icon_path: String = "res://assets/abilities/" + icon_name if icon_name != "" else ""
			var effects: Array = item_dict.get("effects", [])
			var detail_text: String = str(effects[0]) if not effects.is_empty() else ""
			item_cell.setup_placeholder(str(item_dict.get("name", "Unknown Materia")), detail_text, {"icon_path": icon_path})
		else:
			item_cell.setup_from_item_data(item_dict, {})
		item_cell.set_clickable(true)
		item_cell.pressed.connect(_on_equip_item_selected.bind(item_instance_id))

func _on_equip_item_selected(item_id: String) -> void:
	var instance_id: String = current_unit_inst.get("instance_id", "")
	UnitService.request_equip_item(instance_id, current_slot_id, item_id)
	UIManager.pop()
