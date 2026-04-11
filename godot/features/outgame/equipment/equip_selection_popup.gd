extends Control

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

	var remove_btn: Button = Button.new()
	remove_btn.text = "Remove"
	remove_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_btn.custom_minimum_size = Vector2(0, 60)
	remove_btn.pressed.connect(_on_equip_item_selected.bind(""))
	equip_selection_list.add_child(remove_btn)

	var unit_data: Dictionary = DataManager.game_data_units.get(current_unit_inst.get("unit_id", ""), {})
	var allowed_equips: Array = unit_data.get("equip", [])

	var available_items: Array = DataManager.get_available_equipment_for_slot(current_slot_id, allowed_equips)

	for item_dict in available_items:
		var item_instance_id: String = item_dict.get("instance_id", "")
		var btn: Button = Button.new()
		btn.text = item_dict.get("name", "Unknown")
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 60)
		btn.pressed.connect(_on_equip_item_selected.bind(item_instance_id))
		equip_selection_list.add_child(btn)

func _on_equip_item_selected(item_id: String) -> void:
	var instance_id: String = current_unit_inst.get("instance_id", "")
	DataManager.request_equip_item(instance_id, current_slot_id, item_id)
	UIManager.pop()
