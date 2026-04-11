extends Control

@onready var shop_feedback_label: Label = $VBoxContainer/ShopFeedbackLabel
@onready var items_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/ItemsContainer
@onready var equipment_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/EquipmentContainer
@onready var item_row_template: PackedScene = preload("res://features/outgame/shop/ShopItemRow.tscn")

var shop_items: Array[String] = ["101000100", "101001100"]
var shop_equipments: Array[String] = ["301000200", "403043300", "405000200"]

func _ready() -> void:
	DataManager.purchase_successful.connect(_on_purchase_successful)
	DataManager.purchase_failed.connect(_on_purchase_failed)
	_populate_shop(shop_items, items_container, "items")
	_populate_shop(shop_equipments, equipment_container, "equipments")

func _populate_shop(ids: Array, container: Control, type: String) -> void:
	for child in container.get_children():
		child.queue_free()
		
	for id in ids:
		var data: Dictionary = {}
		if DataManager.game_data_items.has(id):
			data = DataManager.game_data_items[id]
		elif DataManager.game_data_equipment.has(id):
			data = DataManager.game_data_equipment[id]
			
		if not data.is_empty():
			var row = item_row_template.instantiate()
			container.add_child(row)
			row.setup(id, data, type)
			row.buy_requested.connect(_on_buy_requested)

func _on_buy_requested(id: String, type: String) -> void:
	DataManager.request_buy_item(id, 1)

func _on_purchase_successful() -> void:
	shop_feedback_label.text = "Item purchased successfully!"

func _on_purchase_failed(error_message: String) -> void:
	shop_feedback_label.text = error_message
