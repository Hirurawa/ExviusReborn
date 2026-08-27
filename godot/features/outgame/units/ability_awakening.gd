extends Control

const MagicScene: PackedScene = preload("res://features/shared/Skill.tscn")

@onready var back_button: Button = $UnitNamebgChara/UnitMinibutton1
@onready var gil_label: Label = $Button/unit_classup_need_money_number
@onready var awaken_button: TextureButton = $Button/unit_classup_button_evo
@onready var before_skill_texture: Control = $Control/sublimation_frame_1/Control
@onready var before_desc: Label = $Control/sublimation_frame_detail_1
@onready var after_skill_texture: Control = $Control/sublimation_frame_2/Control
@onready var after_desc: RichTextLabel = $Control/sublimation_frame_detail_2
@onready var result_text_label: Label = $Button/unit_classup_check_result_text

@onready var material_nodes: Array[Control] = [
	$Material1,
	$Material2,
	$Material3,
	$Material4,
	$Material5,
]

var _texture_cache: Dictionary = {}

var before_skill_id: int = -1
var unit_instance: Dictionary = {}
var awakening: Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	awaken_button.pressed.connect(_on_awaken_pressed)
	#init_scene({"before_skill_id": 20080})


func init_scene(params: Dictionary) -> void:
	if params.has("before_skill_id"):
		before_skill_id = params.get("before_skill_id", -1)
	if params.has("unit_instance"):
		unit_instance = params.get("unit_instance", {})
	awakening = GameDatabase.get_skill_awakening_info(before_skill_id)
	_refresh_skill_textures()
	_populate_awakening_requirements()
	_refresh_button_state()

# TODO: Make prettier. This is a mess.
func _refresh_skill_textures() -> void:
	var before_panel: Control = MagicScene.instantiate()
	var after_panel: Control = MagicScene.instantiate()
	var after_skill_data
	var before_skill_data = GameDatabase.get_magic(before_skill_id)
	before_desc.text = awakening.get("beforeExplain")
	after_desc.text = awakening.get("afterExplain")
	var temp = unit_instance.get("final_stats").get("skills").get("magic").filter(func(x): return x["id"] == str(before_skill_id))
	if not before_skill_data.is_empty():
		before_panel.setup_from_skill_data(before_skill_data, "Trait", temp[0].get("awaken_level"))
		before_skill_texture.add_child(before_panel)
		after_skill_data = GameDatabase.get_magic(awakening.get("afterSkillId"))
		after_panel.setup_from_skill_data(after_skill_data, "Trait", int(temp[0].get("awaken_level"))+1)
		after_skill_texture.add_child(after_panel)
	else:
		before_skill_data = GameDatabase.get_ability(before_skill_id)
		temp = unit_instance.get("final_stats").get("skills").get("ability").filter(func(x): return x["id"] == str(before_skill_id))
		if not before_skill_data.is_empty():
			before_panel.setup_from_skill_data(before_skill_data, "Trait", temp[0].get("awaken_level"))
			before_skill_texture.add_child(before_panel)
			after_skill_data = GameDatabase.get_ability(awakening.get("afterSkillId"))
			after_panel.setup_from_skill_data(after_skill_data, "Trait", int(temp[0].get("awaken_level"))+1)
			after_skill_texture.add_child(after_panel)
		else:
			before_skill_data = GameDatabase.get_passive(before_skill_id)
			temp = unit_instance.get("final_stats").get("skills").get("passive").filter(func(x): return x["id"] == str(before_skill_id))
			if not before_skill_data.is_empty():
				before_panel.setup_from_skill_data(before_skill_data, "Trait", temp[0].get("awaken_level"))
				before_skill_texture.add_child(before_panel)
				after_skill_data = GameDatabase.get_passive(awakening.get("afterSkillId"))
				after_panel.setup_from_skill_data(after_skill_data, "Trait", int(temp[0].get("awaken_level"))+1)
				after_skill_texture.add_child(after_panel)
			


func _populate_awakening_requirements() -> void:
	if gil_label != null:
		gil_label.text = str(int(awakening.get("gil", 0)))

	var materials: Dictionary = {}
	for item in str(awakening.get("material", "")).split(',', false):
		var parts := item.split(":")
		if parts.size() >= 3:
			materials[parts[1]] = parts[2].to_int()
	var material_ids: Array = materials.keys()

	var stackables_var: Variant = InventoryService.owned_items.get("stackables", {})
	var stackables: Dictionary = stackables_var as Dictionary if stackables_var is Dictionary else {}

	for i in range(material_nodes.size()):
		var slot: Control = material_nodes[i]
		if slot == null:
			continue
		if i >= material_ids.size():
			slot.visible = false
			continue
		var item_id: int = int(material_ids[i])
		var count: int = int(materials[material_ids[i]])
		var item_data: Dictionary = GameDatabase.get_item(item_id)

		var icon_node: TextureRect = slot.get_node_or_null("unit_classup_item_icon") as TextureRect
		if icon_node != null:
			var icon_name: String = str(item_data.get("iconFile", ""))
			var tex: Texture2D = null
			if icon_name != "":
				tex = _load_cached_texture("res://assets/items/" + icon_name)
			icon_node.texture = tex

		var num_node: Label = slot.get_node_or_null("unit_classup_item_num") as Label
		if num_node != null:
			num_node.text = "x " + str(count)

		var name_node: Label = slot.get_node_or_null("unit_classup_item_name") as Label
		if name_node != null:
			name_node.text = str(item_data.get("name", item_id))

		var have_node: Label = slot.get_node_or_null("unit_classup_item_have") as Label
		if have_node != null:
			var owned_count: int = int(stackables.get(str(item_id), 0))
			have_node.text = str(owned_count)
			if owned_count < count:
				have_node.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
			else:
				have_node.remove_theme_color_override("font_color")

		slot.visible = true


func _load_cached_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not ResourceLoader.exists(path):
		_texture_cache[path] = null
		return null
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex


func _refresh_button_state() -> void:
	var status: Dictionary = UnitService.can_awaken_ability(before_skill_id)
	var can_awaken: bool = bool(status.get("ok", false))
	var reason: String = str(status.get("reason", ""))

	if awaken_button != null:
		awaken_button.visible = true
		awaken_button.disabled = not can_awaken
	if result_text_label != null:
		if can_awaken:
			result_text_label.visible = false
		else:
			result_text_label.text = reason
			result_text_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
			result_text_label.visible = reason != ""


func _on_awaken_pressed() -> void:
	var response: Dictionary = UnitService.awaken_ability(before_skill_id, unit_instance.get("instance_id"))
	if bool(response.get("success", false)):
		_populate_awakening_requirements()
		_refresh_button_state()
		_show_result_popup("Awakening successful!")
	else:
		_show_result_popup(str(response.get("error", "Awakening failed")))
		pass


func _show_result_popup(message: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Awakening Result"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)


func _on_back_pressed() -> void:
	UIManager.pop()
