extends PanelContainer

signal buy_requested(item_id: String, type: String)

@onready var icon_rect: TextureRect = $HBoxContainer/IconRect
@onready var name_label: Label = $HBoxContainer/VBoxContainer/NameLabel
@onready var desc_label: Label = $HBoxContainer/VBoxContainer/DescLabel
@onready var price_label: Label = $HBoxContainer/VBoxContainer2/PriceLabel
@onready var buy_button: Button = $HBoxContainer/VBoxContainer2/BuyButton

var _item_id: String
var _type: String

static var _texture_cache: Dictionary = {}

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _ready() -> void:
	buy_button.pressed.connect(_on_buy_pressed)

func setup(id: String, data: Dictionary, type: String) -> void:
	_item_id = id
	_type = type
	
	name_label.text = data.get("name", "Unknown")
	price_label.text = str(int(data.get("price_buy", 0))) + " Gil"
	
	var strings: Dictionary = data.get("strings", {})
	var desc_short_list: Array = strings.get("desc_short", [])
	var desc_text: String = ""
	for entry in desc_short_list:
		if entry != null and str(entry) != "":
			desc_text = str(entry)
			break
	desc_label.text = desc_text
		
	var icon_name: String = data.get("icon", "")
	if icon_name != "":
		# Determine correct folder based on what exists
		var item_tex: Texture2D = _get_dynamic_texture("res://assets/items/" + icon_name) if ResourceLoader.exists("res://assets/items/" + icon_name) else null
		if item_tex:
			icon_rect.texture = item_tex
		else:
			# It might be in equipment, or global_equip, etc.
			var equip_tex: Texture2D = _get_dynamic_texture("res://assets/equip/" + icon_name) if ResourceLoader.exists("res://assets/equip/" + icon_name) else null
			if equip_tex:
				icon_rect.texture = equip_tex

func _on_buy_pressed() -> void:
	buy_requested.emit(_item_id, _type)
