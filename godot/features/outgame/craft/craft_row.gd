extends PanelContainer

signal craft_requested(item_id: String, quantity: int)

@onready var icon_rect: TextureRect = $HBoxContainer/IconRect
@onready var name_label: Label = $HBoxContainer/VBoxContainer/NameLabel
@onready var material_label: Label = $HBoxContainer/VBoxContainer/MaterialLabel
@onready var price_label: Label = $HBoxContainer/VBoxContainer2/PriceLabel
@onready var craft_button: Button = $HBoxContainer/VBoxContainer2/HBoxContainer/CraftButton

var _recipe_id: String

static var _texture_cache: Dictionary = {}

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _ready() -> void:
	craft_button.pressed.connect(_on_craft_pressed)

func setup(data: Dictionary) -> void:
	name_label.text = str(data.get("name", "Unknown"))
	price_label.text = str(int(data.get("gil", 0))) + " Gil"
	
	_recipe_id = str(data.get("recipeId"))
	
	var material_text = str(data.get("material", ""))
	var material_array: Array
	if material_text != null:
		if material_text.contains(','):
			material_array = material_text.split(',')
		else:
			material_array = [material_text]
			
	var mat_text: Array[String] = []
	for mat in material_array:
		var mat_data = mat.split(':')
		if mat_data[0] == "20":
			mat_text.append(str(mat_data[2]) + "x " + GameDatabase.get_item(int(mat_data[1])).get("name"))
		if mat_data[0] == "21":
			mat_text.append(str(mat_data[2]) + "x " + GameDatabase.get_equipment(int(mat_data[1])).get("name"))
		if mat_data[0] == "22":
			mat_text.append(str(mat_data[2]) + "x " + GameDatabase.get_materia(int(mat_data[1])).get("name"))
		
	material_label.text = " - ".join(mat_text)
	
	var icon_name: String = data.get("iconFile", "")
	if icon_name != "":
		var item_tex: Texture2D = _get_dynamic_texture("res://assets/items/" + icon_name) if ResourceLoader.exists("res://assets/items/" + icon_name) else null
		if item_tex:
			icon_rect.texture = item_tex

func _on_craft_pressed() -> void:
	craft_requested.emit(_recipe_id, 1)
