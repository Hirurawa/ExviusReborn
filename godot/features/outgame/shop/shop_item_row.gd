extends PanelContainer

signal buy_requested(item_id: String, type: String)

@onready var icon_rect = $HBoxContainer/IconRect
@onready var name_label = $HBoxContainer/VBoxContainer/NameLabel
@onready var desc_label = $HBoxContainer/VBoxContainer/DescLabel
@onready var price_label = $HBoxContainer/VBoxContainer2/PriceLabel
@onready var buy_button = $HBoxContainer/VBoxContainer2/BuyButton

var _item_id: String
var _type: String

func _ready():
	buy_button.pressed.connect(_on_buy_pressed)

func setup(id: String, data: Dictionary, type: String):
	_item_id = id
	_type = type
	
	name_label.text = data.get("name", "Unknown")
	price_label.text = str(int(data.get("price_buy", 0))) + " Gil"
	
	var strings = data.get("strings", {})
	var desc_short_list = strings.get("desc_short", [])
	if desc_short_list and desc_short_list.size() > 0:
		desc_label.text = desc_short_list[0]
	else:
		desc_label.text = ""
		
	var icon_name = data.get("icon", "")
	if icon_name != "":
		# Determine correct folder based on what exists
		var item_tex = ResourceLoader.load("res://assets/items/" + icon_name) if ResourceLoader.exists("res://assets/items/" + icon_name) else null
		if item_tex:
			icon_rect.texture = item_tex
		else:
			# It might be in equipment, or global_equip, etc.
			var equip_tex = ResourceLoader.load("res://assets/equip/" + icon_name) if ResourceLoader.exists("res://assets/equip/" + icon_name) else null
			if equip_tex:
				icon_rect.texture = equip_tex

func _on_buy_pressed():
	buy_requested.emit(_item_id, _type)
