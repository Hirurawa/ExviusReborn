extends Control

@onready var shop_potion_name = $VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer/NameLabel
@onready var shop_potion_desc = $VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer/DescLabel
@onready var shop_potion_icon = $VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/IconRect
@onready var add_potion_button = $VBoxContainer/ScrollContainer/ShopListContainer/PotionItem/HBoxContainer/VBoxContainer2/AddPotionButton
@onready var shop_feedback_label = $VBoxContainer/ShopFeedbackLabel

func _ready():
	add_potion_button.pressed.connect(_on_add_potion_pressed)

	var potion_data = DataManager.game_data_items.get("101000100", {})
	if potion_data:
		shop_potion_name.text = potion_data.get("name", "Potion")
		var strings = potion_data.get("strings", {})
		var desc_short_list = strings.get("desc_short", [])
		if desc_short_list and desc_short_list.size() > 0:
			shop_potion_desc.text = desc_short_list[0]
		var icon_name = potion_data.get("icon", "")
		if icon_name != "":
			var tex = load("res://assets/items/" + icon_name)
			if tex:
				shop_potion_icon.texture = tex

func _on_add_potion_pressed():
	var result = await DataManager.buy_item("101000100", 1)
	if result.has("error"):
		shop_feedback_label.text = result.error
	else:
		shop_feedback_label.text = "Potion purchased successfully!"
