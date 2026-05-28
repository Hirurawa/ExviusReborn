extends Control

@onready var shop_feedback_label: Label = $VBoxContainer/ShopFeedbackLabel
@onready var items_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/ItemsContainer
@onready var equipment_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/EquipmentContainer
@onready var item_row_template: PackedScene = preload("res://features/outgame/shop/ShopItemRow.tscn")

var shop_items: Array[String] = ["101000100", "101001100", "106301900", "106302000", "106302100", "106302200", "106302300", "106302600", "290010000", "290010100", "290010200", "290020000", "290020100", "290020200", "290020300", "290020400", "290020500", "290020600", "290020700", "290020800", "290020900", "290030000", "290030100", "290030200", "290030300", "290030400", "290030500", "290030600", "290030700", "290030800", "290030900", "290031000", "290040000", "290040100", "290040200", "290040300", "290040400", "290050100", "290050200", "290050300", "290050400", "290050500", "290060000", "290060100", "290060200", "290060400", "291000100", "291000200", "291000300", "291000400", "291000500", "291100100", "291100200", "291100300", "292000100", "292000200", "292000300", "292000400", "292000500", "292000600", "293000100", "293000200", "1209000845", "1209002041"]
var shop_equipments: Array[String] = ["301000200", "403043300", "405000200"]

func _ready() -> void:
	InventoryService.purchase_successful.connect(_on_purchase_successful)
	InventoryService.purchase_failed.connect(_on_purchase_failed)
	_populate_shop(shop_items, items_container, "items")
	_populate_shop(shop_equipments, equipment_container, "equipments")

func _populate_shop(ids: Array, container: Control, type: String) -> void:
	for child in container.get_children():
		child.queue_free()
		
	for id in ids:
		var data: Dictionary = {}
		if StaticData.game_data_items.has(id):
			data = StaticData.game_data_items[id]
		elif StaticData.game_data_equipment.has(id):
			data = StaticData.game_data_equipment[id]
			
		if not data.is_empty():
			var row = item_row_template.instantiate()
			container.add_child(row)
			row.setup(id, data, type)
			row.buy_requested.connect(_on_buy_requested)

func _on_buy_requested(id: String, type: String) -> void:
	InventoryService.request_buy_item(id, 1)

func _on_purchase_successful() -> void:
	shop_feedback_label.text = "Item purchased successfully!"

func _on_purchase_failed(error_message: String) -> void:
	shop_feedback_label.text = _friendly_purchase_error(error_message)

func _friendly_purchase_error(error_message: String) -> String:
	match error_message:
		"ERR_INSUFFICIENT_RESOURCES", "ERR_INSUFFICENT_RESOURCES":
			return "Not enough gil to purchase this item."
		"ERR_MISSING_SERVER_ERROR_MSG":
			return "Purchase failed. Please try again."
		_:
			return "Purchase failed: %s" % error_message
