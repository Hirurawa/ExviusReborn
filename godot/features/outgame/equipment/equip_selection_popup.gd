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

	for item in DataManager.owned_items:
		if not item is Dictionary: continue
		var item_id: String = item.get("item_id", "")
		var item_data: Variant = DataManager.game_data_equipment.get(item_id)
		if not item_data: continue

		# Ensure we only work with Dictionary
		var item_data_dict: Dictionary = item_data as Dictionary

		var item_type: String = item_data_dict.get("type", "")
		var item_type_id: int = item_data_dict.get("type_id", -1)
		var is_valid_slot: bool = false

		var item_slot: String = item_data_dict.get("slot", "")
		if "hand" in current_slot_id and (item_slot == "Weapon" or item_slot == "Shield"):
			is_valid_slot = true
		elif "head" in current_slot_id and item_slot == "Headgear":
			is_valid_slot = true
		elif "body" in current_slot_id and item_slot == "Chest":
			is_valid_slot = true
		elif "acc_" in current_slot_id and item_slot == "Accessory":
			is_valid_slot = true
		elif "ability_" in current_slot_id and item_slot == "Materia":
			is_valid_slot = true

		if not is_valid_slot: continue
		if item_type_id not in allowed_equips and item_type_id != -1: continue

		var btn: Button = Button.new()
		btn.text = item_data_dict.get("name", "Unknown")
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 60)
		btn.pressed.connect(_on_equip_item_selected.bind(item_id))
		equip_selection_list.add_child(btn)

func _on_equip_item_selected(item_id: String) -> void:
	var instance_id: String = current_unit_inst.get("instance_id", "")

	if item_id != "" and current_slot_id in ["r_hand", "l_hand"]:
		var item_data: Dictionary = DataManager.game_data_equipment.get(item_id, {})
		if item_data.get("is_twohanded", false):
			var other_hand: String = "l_hand" if current_slot_id == "r_hand" else "r_hand"
			await DataManager.equip_item(instance_id, other_hand, "")

	await DataManager.equip_item(instance_id, current_slot_id, item_id)
	UIManager.pop()
